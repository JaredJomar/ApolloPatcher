#import "header.h"
#import "fishhook.h"
#import "Patches/ApolloWebAuthViewController.h"
#import "Patches/ApolloWebTransport.h"
#import "SettingsController.h"

static NSString *randomUserAgent = [NSString stringWithFormat:@"iOS: com.%@.%@ v%d.%d.%d (by /u/%@)", RANDSTRING, RANDSTRING, RANDINT, RANDINT, RANDINT, RANDSTRING];
// Memo iPad6 17.5.1
// Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.5 Safari/605.1.15
static NSString *const safariUserAgent = @"Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.5 Safari/605.1.15";
%group CustomID
%hook RDKOAuthCredential
// reddit client id
- (id)clientIdentifier {
    if (kCustomID) {
        return kCustomID;
    }
    return %orig;
}
// custom redirect URI (Dystopia default) so OAuth completes against the configured app
- (NSURL *)redirectURI {
    if (kRedirectURI.length > 0) {
        NSURL *url = [NSURL URLWithString:kRedirectURI];
        if (url) {
            return url;
        }
    }
    return %orig;
}
%end

%hook RDKClient
// Configured User-Agent (Dystopia default) or randomized
- (id)userAgent {
    if (kUserAgent.length > 0) {
        return kUserAgent;
    }
    return randomUserAgent;
}
%end
%end

%group CustomOAuth

static const char kARScheme     = '\0';
static const char kARAuthURL    = '\0';
static const char kARCompletion = '\0';

// Replace ASWebAuthenticationSession with a WKWebView-based flow when the
// configured redirect URI scheme (e.g. dystopia://response) isn't registered in
// Apollo's CFBundleURLTypes, so the native session couldn't route the callback
// back to the app. WKNavigationDelegate fires for every URL before iOS routing,
// so the callback can be intercepted regardless of the scheme.
%hook ASWebAuthenticationSession

- (instancetype)initWithURL:(NSURL *)URL
        callbackURLScheme:(NSString *)callbackURLScheme
        completionHandler:(void (^)(NSURL *, NSError *))completionHandler {
    id result = %orig(URL, callbackURLScheme, completionHandler);
    id target = result ?: self;
    objc_setAssociatedObject(target, &kARScheme,     callbackURLScheme, OBJC_ASSOCIATION_COPY);
    objc_setAssociatedObject(target, &kARAuthURL,    URL,               OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(target, &kARCompletion, completionHandler, OBJC_ASSOCIATION_COPY);
    return result;
}

- (BOOL)start {
    NSURL *authURL = objc_getAssociatedObject(self, &kARAuthURL);
    void (^completion)(NSURL *, NSError *) = objc_getAssociatedObject(self, &kARCompletion);
    if (!authURL || !completion) {
        return %orig;
    }

    // Ensure the OAuth grant carries every scope Apollo functionality needs.
    // Tokens freeze scopes at grant time, so this must run before ANY login
    // path (native apollo:// callback or our WKWebView interception).
    // Missing scopes surface as: saved posts never persist (/api/save 403),
    // votes/messages failing. NOTE: requesting scopes absent from Reddit's
    // official scope list breaks the grant; adult content is account-level.
    {
        NSURLComponents *components = [NSURLComponents componentsWithURL:authURL resolvingAgainstBaseURL:NO];
        NSArray<NSString *> *requiredScopes = @[
            @"identity", @"edit", @"flair", @"history", @"modconfig", @"modflair",
            @"modlog", @"modposts", @"modwiki", @"mysubreddits", @"privatemessages",
            @"read", @"report", @"save", @"submit", @"subscribe", @"vote",
            @"wikiedit", @"wikiread",
        ];
        if (components) {
            NSMutableArray *queryItems = [components.queryItems mutableCopy];
            if (!queryItems) queryItems = [NSMutableArray array];

            NSURLQueryItem *scopeItem = nil;
            for (NSURLQueryItem *item in queryItems) {
                if ([item.name isEqualToString:@"scope"]) {
                    scopeItem = item;
                    break;
                }
            }

            NSMutableSet *present = [NSMutableSet set];
            NSMutableArray *existingParts = [NSMutableArray array];
            if (scopeItem.value.length) {
                // Grant strings separate scopes with '+' or encoded spaces.
                for (NSString *part in [scopeItem.value componentsSeparatedByCharactersInSet:
                        [NSCharacterSet characterSetWithCharactersInString:@"+ "]]) {
                    if (part.length) {
                        [present addObject:part];
                        [existingParts addObject:part];
                    }
                }
            }

            NSMutableArray *missing = [NSMutableArray array];
            for (NSString *required in requiredScopes) {
                if (![present containsObject:required]) [missing addObject:required];
            }

            if (missing.count > 0) {
                [existingParts addObjectsFromArray:missing];
                if (scopeItem) [queryItems removeObject:scopeItem];
                [queryItems addObject:[NSURLQueryItem queryItemWithName:@"scope"
                                                                  value:[existingParts componentsJoinedByString:@"+"]]];
                components.queryItems = queryItems;
                authURL = components.URL;
                NSLog(@"[WebAuth] ensured OAuth scopes, added: %@",
                      [missing componentsJoinedByString:@", "]);
            }
        }
    }

    // Prefer the full redirect_uri from the (possibly scope-updated) auth URL
    // (set by our RDKOAuthCredential hook). Falls back to the callback scheme otherwise.
    NSString *callbackScheme = objc_getAssociatedObject(self, &kARScheme);
    NSString *interceptRedirectURI = callbackScheme.length ? [callbackScheme stringByAppendingString:@"://"] : nil;
    for (NSURLQueryItem *item in [NSURLComponents componentsWithURL:authURL resolvingAgainstBaseURL:NO].queryItems) {
        if ([item.name isEqualToString:@"redirect_uri"]) {
            if (item.value.length) interceptRedirectURI = item.value;
            break;
        }
    }

    // Apollo's own scheme routes natively; only replace the session for custom
    // schemes (e.g. dystopia://response) iOS can't deliver back to the app.
    if (interceptRedirectURI.length == 0 || [interceptRedirectURI hasPrefix:@"apollo://"]) {
        return %orig;
    }

    UIWindow *window = nil;
    if (@available(iOS 13.0, *)) {
        for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
            if (scene.activationState == UISceneActivationStateForegroundActive
                    && [scene isKindOfClass:[UIWindowScene class]]) {
                NSArray<UIWindow *> *sceneWindows = ((UIWindowScene *)scene).windows;
                for (UIWindow *candidate in sceneWindows) {
                    if (candidate.isKeyWindow) { window = candidate; break; }
                }
                window = window ?: sceneWindows.firstObject;
                if (window) break;
            }
        }
    }
    window = window ?: [UIApplication sharedApplication].keyWindow;
    if (!window) {
        return %orig;
    }

    NSLog(@"ApolloPatcher:[WebAuth] using WKWebView, intercepting redirectURI=%@", interceptRedirectURI);

    ApolloWebAuthViewController *authVC = [[ApolloWebAuthViewController alloc]
        initWithURL:authURL redirectURI:interceptRedirectURI completionHandler:completion];
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:authVC];
    nav.modalPresentationStyle = UIModalPresentationFormSheet;

    UIViewController *top = window.rootViewController;
    while (top.presentedViewController) top = top.presentedViewController;
    [top presentViewController:nav animated:YES completion:nil];

    return YES;
}

%end

@interface NSURLSession (Private)
- (BOOL)isJSONResponse:(NSURLResponse *)response;
- (void)useDummyDataWithCompletionHandler:(void (^)(NSData *, NSURLResponse *, NSError *))completionHandler;
@end

%hook NSURLSession
// Imgur Upload
- (NSURLSessionUploadTask*)uploadTaskWithRequest:(NSURLRequest*)request fromData:(NSData*)bodyData completionHandler:(void (^)(NSData*, NSURLResponse*, NSError*))completionHandler {
    NSString *urlString = [[request URL] absoluteString];
    NSString *oldPrefix = @"https://imgur-apiv3.p.rapidapi.com/3/image";
    NSString *newPrefix = @"https://api.imgur.com/3/image";
    //NSLog(@"uploadTaskWithRequest:%@", urlString);
    if ([urlString isEqualToString:oldPrefix]) {
        NSMutableURLRequest *modifiedRequest = [request mutableCopy];
        [modifiedRequest setURL:[NSURL URLWithString:newPrefix]];

        // Hacky fix for multi-image upload failures - the first attempt may fail but subsequent attempts will succeed
        dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);
        void (^newCompletionHandler)(NSData*, NSURLResponse*, NSError*) = ^(NSData *data, NSURLResponse *response, NSError *error) {
            completionHandler(data, response, error);
            dispatch_semaphore_signal(semaphore);
        };
        NSURLSessionUploadTask *task = %orig(modifiedRequest,bodyData,newCompletionHandler);
        [task resume];
        dispatch_semaphore_wait(semaphore, DISPATCH_TIME_FOREVER);
        return task;
    }
    return %orig();
}
// Imgur Delete and album creation
- (NSURLSessionDataTask*)dataTaskWithRequest:(NSURLRequest*)request completionHandler:(void (^)(NSData*, NSURLResponse*, NSError*))completionHandler {
    NSString *urlString = [[request URL] absoluteString];
    NSString *oldImagePrefix = @"https://imgur-apiv3.p.rapidapi.com/3/image/";
    NSString *newImagePrefix = @"https://api.imgur.com/3/image/";
    NSString *oldAlbumPrefix = @"https://imgur-apiv3.p.rapidapi.com/3/album";
    NSString *newAlbumPrefix = @"https://api.imgur.com/3/album";
    //NSLog(@"dataTaskWithRequest:%@", urlString);
    if ([urlString hasPrefix:oldImagePrefix]) {
        NSString *suffix = [urlString substringFromIndex:oldImagePrefix.length];
        NSString *newUrlString = [newImagePrefix stringByAppendingString:suffix];
        NSMutableURLRequest *modifiedRequest = [request mutableCopy];
        [modifiedRequest setURL:[NSURL URLWithString:newUrlString]];
        return %orig(modifiedRequest,completionHandler);
    } else if ([urlString isEqualToString:oldAlbumPrefix]) {
        NSMutableURLRequest *modifiedRequest = [request mutableCopy];
        [modifiedRequest setURL:[NSURL URLWithString:newAlbumPrefix]];
        return %orig(modifiedRequest,completionHandler);
    }
    return %orig();
}
// Fix Imgur loading issue
static NSString *imageID;
- (NSURLSessionDataTask *)dataTaskWithURL:(NSURL *)url completionHandler:(void (^)(NSData *, NSURLResponse *, NSError *))completionHandler {
    //NSLog(@"dataTaskWithURL:dataTaskWithURL:%@", url.absoluteString);
    imageID = [url.lastPathComponent stringByDeletingPathExtension];
    // Remove unwanted messages on app startup
    if ([url.absoluteString containsString:@"https://apollogur.download/api/apollonouncement"] ||
        [url.absoluteString containsString:@"https://apollogur.download/api/easter_sale"] ||
        [url.absoluteString containsString:@"https://apollogur.download/api/html_codes"] ||
        [url.absoluteString containsString:@"https://apollogur.download/api/refund_screen_config"]) {
        return nil;
    } else if ([url.absoluteString containsString:@"https://apollogur.download/api/image/"]) {
        NSString *modifiedURLString = [NSString stringWithFormat:@"https://api.imgur.com/3/image/%@.json?client_id=%@", imageID, kClientID];
        NSURL *modifiedURL = [NSURL URLWithString:modifiedURLString];
        // Access the modified URL to get the actual data
        NSURLSessionDataTask *dataTask = [self dataTaskWithURL:modifiedURL completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
            if (error || ![self isJSONResponse:response]) {
                // If an error occurs or the response is not a JSON response, dummy data is used
                [self useDummyDataWithCompletionHandler:completionHandler];
            } else {
                // If normal data is returned, the callback is executed
                completionHandler(data, response, error);
            }
        }];

        [dataTask resume];
        return dataTask;
    } else if ([url.absoluteString containsString:@"https://apollogur.download/api/album/"]) {
        NSString *modifiedURLString = [NSString stringWithFormat:@"https://api.imgur.com/3/album/%@.json?client_id=%@", imageID, kClientID];
        NSURL *modifiedURL = [NSURL URLWithString:modifiedURLString];
        return %orig(modifiedURL, completionHandler);
    }
    return %orig;
}
%new
- (BOOL)isJSONResponse:(NSURLResponse *)response {
    if ([response isKindOfClass:[NSHTTPURLResponse class]]) {
        NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)response;
        NSString *contentType = httpResponse.allHeaderFields[@"Content-Type"];
        if (contentType && [contentType rangeOfString:@"application/json" options:NSCaseInsensitiveSearch].location != NSNotFound) {
            return YES;
        }
    }
    return NO;
}
%new
- (void)useDummyDataWithCompletionHandler:(void (^)(NSData *, NSURLResponse *, NSError *))completionHandler {
    // Create dummy data
    NSDictionary *dummyData = @{
        @"data": @{
            @"id": @"example_id",
            @"title": @"Example Image",
            @"description": @"This is an example image",
            @"datetime": @(1234567890),
            @"type": @"image/gif",
            @"animated": @(YES),
            @"width": @(640),
            @"height": @(480),
            @"size": @(1024),
            @"views": @(100),
            @"bandwidth": @(512),
            @"vote": @(0),
            @"favorite": @(NO),
            @"nsfw": @(NO),
            @"section": @"example",
            @"account_url": @"example_user",
            @"account_id": @"example_account_id",
            @"is_ad": @(NO),
            @"in_most_viral": @(NO),
            @"has_sound": @(NO),
            @"tags": @[@"example", @"image"],
            @"ad_type": @"image",
            @"ad_url": @"https://example.com",
            @"edited": @(0),
            @"in_gallery": @(NO),
            @"deletehash": @"abc123deletehash",
            @"name": @"example_image",
            @"link": [NSString stringWithFormat:@"https://i.imgur.com/%@.gif", imageID],
            @"success": @(YES)
        }
    };

    NSError *error;
    NSData *dummyDataJSON = [NSJSONSerialization dataWithJSONObject:dummyData options:0 error:&error];

    if (error) {
        NSLog(@"JSON conversion error for dummy data: %@", error);
        return;
    }

    NSHTTPURLResponse *response = [[NSHTTPURLResponse alloc] initWithURL:[NSURL URLWithString:@"https://apollogur.download/api/image/"] statusCode:200 HTTPVersion:@"HTTP/1.1" headerFields:@{@"Content-Type": @"application/json"}];

    completionHandler(dummyDataJSON, response, nil);
}
%end

@interface __NSCFLocalSessionTask : NSObject <NSCopying, NSProgressReporting>
@end

%hook __NSCFLocalSessionTask
- (void)_onqueue_resume {
    // Grab the request url
    NSURLRequest *request =  [self valueForKey:@"_originalRequest"];
    NSString *requestURL = request.URL.absoluteString;
    //NSLog(@"requestURL:%@", requestURL);
    // Log the User-Agent header
    //NSString *userAgent = [request valueForHTTPHeaderField:@"User-Agent"];
    //NSLog(@"User-Agent: %@", userAgent);
    // Drop requests to analytics/apns services
    if ([requestURL containsString:@"https://apollopushserver.xyz"] ||
        [requestURL containsString:@"telemetrydeck.com"] ||
        [requestURL containsString:@"https://sessions.bugsnag.com"] ||
        [requestURL containsString:@"https://api.mixpanel.com"] ||
        [requestURL containsString:@"https://api.statsig.com"] ||
        [requestURL containsString:@"https://apolloreq.com/api/req_v2"] ||
        [requestURL containsString:@"https://apollogur.download/api/goodbye_wallpaper/"]) {
        return;
    }
    // Intercept modified "unproxied" Imgur requests and replace Authorization header with custom client ID
    NSMutableURLRequest *mutableRequest = [request mutableCopy];
    if ([requestURL containsString:@"https://api.imgur.com/"]) {
        // Insert the api credential and update the request on this session task
        [mutableRequest setValue:[NSString stringWithFormat:@"Client-ID %@", kClientID] forHTTPHeaderField:@"Authorization"];
        // Set or else upload will fail with 400
        if ([requestURL isEqualToString:@"https://api.imgur.com/3/image"]) {
            [mutableRequest setValue:@"image/jpeg" forHTTPHeaderField:@"Content-Type"];
        }
        [self setValue:mutableRequest forKey:@"_originalRequest"];
        [self setValue:mutableRequest forKey:@"_currentRequest"];
    } else if ([requestURL containsString:@"https://oauth.reddit.com/"] || [requestURL containsString:@"https://www.reddit.com/"]) {
        // Optional cookie transport (Reborn-style): route eligible GETs through
        // the harvested web session so they get web-grade treatment. Falls
        // through to the stock OAuth path whenever it declines to act.
        if (ApolloWebTransportEnabled()) {
            NSURLRequest *transportRequest = ApolloWebTransportRewriteRequest(request);
            if (transportRequest) {
                [self setValue:transportRequest forKey:@"_originalRequest"];
                [self setValue:transportRequest forKey:@"_currentRequest"];
                %orig;
                return;
            }
        }
        // reddit has blocked the stock user agent; use the configured one (Dystopia default) or a randomized fallback
        // iOS: com.christianselig.Apollo v1.15.11 (by /u/iamthatis)
        [mutableRequest setValue:(kUserAgent.length > 0 ? kUserAgent : randomUserAgent) forHTTPHeaderField:@"User-Agent"];
        [self setValue:mutableRequest forKey:@"_originalRequest"];
        [self setValue:mutableRequest forKey:@"_currentRequest"];
    } else if ([requestURL containsString:@"redgifs.com"]) {
        // RedGifs blocks non-browser user agents and serves silent video
        [mutableRequest setValue:safariUserAgent forHTTPHeaderField:@"User-Agent"];
        [self setValue:mutableRequest forKey:@"_originalRequest"];
        [self setValue:mutableRequest forKey:@"_currentRequest"];
    }

    %orig;
}
%end

// Credits https://github.com/JeffreyCA/Apollo-ImprovedCustomApi
// Regex for opaque share links
static NSString *const ShareLinkRegexPattern = @"^(?:https?:)?//(?:www\\.)?reddit\\.com/(?:r|u)/(\\w+)/s/(\\w+)$";
static NSRegularExpression *ShareLinkRegex;

// Regex for media share links
static NSString *const MediaShareLinkPattern = @"^(?:https?:)?//(?:www\\.)?reddit\\.com/media\\?url=(.*?)$";
static NSRegularExpression *MediaShareLinkRegex;

// Cache storing resolved share URLs - this is an optimization so that we don't need to resolve the share URL every time
static NSCache <NSString *, ShareUrlTask *> *cache;

@implementation ShareUrlTask
- (instancetype)init {
    self = [super init];
    if (self) {
        _dispatchGroup = NULL;
        _resolvedURL = NULL;
    }
    return self;
}
@end

// Helper functions for resolving share URLs
// Present loading alert on top of current view controller
static UIViewController *PresentResolvingShareLinkAlert() {
    UIViewController *vc = [UIApplication sharedApplication].keyWindow.rootViewController;

    alertController = [UIAlertController alertControllerWithTitle:nil message:@"Resolving share link..." preferredStyle:UIAlertControllerStyleAlert];

    [vc presentViewController:alertController animated:YES completion:nil];
    return alertController;
}
// Strip tracking parameters from resolved share URL
static NSURL *RemoveShareTrackingParams(NSURL *url) {
    NSURLComponents *components = [NSURLComponents componentsWithURL:url resolvingAgainstBaseURL:NO];
    NSMutableArray *queryItems = [NSMutableArray arrayWithArray:components.queryItems];
    [queryItems filterUsingPredicate:[NSPredicate predicateWithFormat:@"name == %@", @"context"]];
    components.queryItems = queryItems;
    return components.URL;
}
// Start async task to resolve share URL
static void StartShareURLResolveTask(NSString *urlString) {
    __block ShareUrlTask *task;
    @synchronized(cache) { // needed?
        task = [cache objectForKey:urlString];
        if (task) {
            return;
        }

        dispatch_group_t dispatch_group = dispatch_group_create();
        task = [[ShareUrlTask alloc] init];
        task.dispatchGroup = dispatch_group;
        [cache setObject:task forKey:urlString];
    }

    NSURL *url = [NSURL URLWithString:urlString];
    dispatch_group_enter(task.dispatchGroup);
    NSURLSessionTask *getTask = [[NSURLSession sharedSession] dataTaskWithURL:url completionHandler:^(NSData * _Nullable data, NSURLResponse * _Nullable response, NSError * _Nullable error) {
        if (!error) {
            NSURL *redirectedURL = [(NSHTTPURLResponse *)response URL];
            NSURL *cleanedURL = RemoveShareTrackingParams(redirectedURL);
            NSString *cleanUrlString = [cleanedURL absoluteString];
            task.resolvedURL = cleanUrlString;
        } else {
            task.resolvedURL = urlString;
        }
        dispatch_group_leave(task.dispatchGroup);
    }];

    [getTask resume];
}
// Asynchronously wait for share URL to resolve
static void TryResolveShareUrl(NSString *urlString, void (^successHandler)(NSString *), void (^ignoreHandler)(void)){
    ShareUrlTask *task = [cache objectForKey:urlString];
    if (!task) {
        // The NSURL initWithString hook might not catch every share URL, so check one more time and enqueue a task if needed
        NSTextCheckingResult *match = [ShareLinkRegex firstMatchInString:urlString options:0 range:NSMakeRange(0, [urlString length])];
        if (!match) {
            ignoreHandler();
            return;
        }
        StartShareURLResolveTask(urlString);
        task = [cache objectForKey:urlString];
    }

    if (task.resolvedURL) {
        successHandler(task.resolvedURL);
        return;
    } else {
        // Wait for task to finish and show loading alert to not block main thread
        UIViewController *shareAlertController = PresentResolvingShareLinkAlert();
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            dispatch_group_wait(task.dispatchGroup, DISPATCH_TIME_FOREVER);
            dispatch_async(dispatch_get_main_queue(), ^{
                [shareAlertController dismissViewControllerAnimated:YES completion:^{
                    successHandler(task.resolvedURL);
                }];
            });
        });
    }
}

// Tappable text link in an inbox item (*not* the links in the PM chat bubbles)
%hook _TtC6Apollo13InboxCellNode
- (void)textNode:(id)textNode tappedLinkAttribute:(id)attr value:(id)val atPoint:(struct CGPoint)point textRange:(struct _NSRange)range {
    if (![val isKindOfClass:[NSURL class]]) {
        %orig;
        return;
    }
    void (^ignoreHandler)(void) = ^{
        %orig;
    };
    void (^successHandler)(NSString *) = ^(NSString *resolvedURL) {
        %orig(textNode, attr, [NSURL URLWithString:resolvedURL], point, range);
    };
    TryResolveShareUrl([val absoluteString], successHandler, ignoreHandler);
}
%end

// Text view containing markdown and tappable links, can be in the header of a post or a comment
%hook _TtC6Apollo12MarkdownNode
- (void)textNode:(id)textNode tappedLinkAttribute:(id)attr value:(id)val atPoint:(struct CGPoint)point textRange:(struct _NSRange)range {
    if (![val isKindOfClass:[NSURL class]]) {
        %orig;
        return;
    }
    void (^ignoreHandler)(void) = ^{
        %orig;
    };
    void (^successHandler)(NSString *) = ^(NSString *resolvedURL) {
        %orig(textNode, attr, [NSURL URLWithString:resolvedURL], point, range);
    };
    TryResolveShareUrl([val absoluteString], successHandler, ignoreHandler);
}
%end

// Tappable link button of a post in a list view (list view refers to home feed, subreddit view, etc.)
%hook _TtC6Apollo13RichMediaNode
- (void)linkButtonTappedWithSender:(_TtC6Apollo14LinkButtonNode *)arg1 {
    RDKLink *rdkLink = MSHookIvar<RDKLink *>(self, "link");
    NSURL *rdkLinkURL;
    if (rdkLink) {
        rdkLinkURL = rdkLink.URL;
    }

    NSURL *url = MSHookIvar<NSURL *>(arg1, "url");
    NSString *urlString = [url absoluteString];

    void (^ignoreHandler)(void) = ^{
        %orig;
    };
    void (^successHandler)(NSString *) = ^(NSString *resolvedURL) {
        NSURL *newURL = [NSURL URLWithString:resolvedURL];
        MSHookIvar<NSURL *>(arg1, "url") = newURL;
        if (rdkLink) {
            MSHookIvar<RDKLink *>(self, "link").URL = newURL;
        }
        %orig;
        MSHookIvar<NSURL *>(arg1, "url") = url;
        MSHookIvar<RDKLink *>(self, "link").URL = rdkLinkURL;
    };
    TryResolveShareUrl(urlString, successHandler, ignoreHandler);
}

- (void)textNode:(id)textNode tappedLinkAttribute:(id)attr value:(id)val atPoint:(struct CGPoint)point textRange:(struct _NSRange)range {
    if (![val isKindOfClass:[NSURL class]]) {
        %orig;
        return;
    }
    void (^ignoreHandler)(void) = ^{
        %orig;
    };
    void (^successHandler)(NSString *) = ^(NSString *resolvedURL) {
        %orig(textNode, attr, [NSURL URLWithString:resolvedURL], point, range);
    };
    TryResolveShareUrl([val absoluteString], successHandler, ignoreHandler);
}
%end

// Single comment under an individual post
%hook _TtC6Apollo15CommentCellNode
- (void)linkButtonTappedWithSender:(_TtC6Apollo14LinkButtonNode *)arg1 {
    %log;
    NSURL *url = MSHookIvar<NSURL *>(arg1, "url");
    NSString *urlString = [url absoluteString];

    void (^ignoreHandler)(void) = ^{
        %orig;
    };
    void (^successHandler)(NSString *) = ^(NSString *resolvedURL) {
        MSHookIvar<NSURL *>(arg1, "url") = [NSURL URLWithString:resolvedURL];
        %orig;
        MSHookIvar<NSURL *>(arg1, "url") = url;
    };
    TryResolveShareUrl(urlString, successHandler, ignoreHandler);
}
%end

// Component at the top of a single post view ("header")
%hook _TtC6Apollo22CommentsHeaderCellNode
- (void)linkButtonNodeTappedWithSender:(_TtC6Apollo14LinkButtonNode *)arg1 {
    RDKLink *rdkLink = MSHookIvar<RDKLink *>(self, "link");
    NSURL *rdkLinkURL;
    if (rdkLink) {
        rdkLinkURL = rdkLink.URL;
    }
    NSURL *url = MSHookIvar<NSURL *>(arg1, "url");
    NSString *urlString = [url absoluteString];

    void (^ignoreHandler)(void) = ^{
        %orig;
    };
    void (^successHandler)(NSString *) = ^(NSString *resolvedURL) {
        NSURL *newURL = [NSURL URLWithString:resolvedURL];
        MSHookIvar<NSURL *>(arg1, "url") = newURL;
        if (rdkLink) {
            MSHookIvar<RDKLink *>(self, "link").URL = newURL;
        }
        %orig;
        MSHookIvar<NSURL *>(arg1, "url") = url;
        MSHookIvar<RDKLink *>(self, "link").URL = rdkLinkURL;
    };
    TryResolveShareUrl(urlString, successHandler, ignoreHandler);
}
%end

%hook NSURL
// Asynchronously resolve share URLs in background
// This is an optimization to "pre-resolve" share URLs so that by the time one taps a share URL it should already be resolved
// On slower network connections, there may still be a loading alert
- (id)initWithString:(id)string {
    NSTextCheckingResult *match = [ShareLinkRegex firstMatchInString:string options:0 range:NSMakeRange(0, [string length])];
    if (match) {
        // This exits early if already in cache
        StartShareURLResolveTask(string);
    }
    // Fix Reddit Media URL redirects, for example this comment: https://reddit.com/r/TikTokCringe/comments/18cyek4/_/kce86er/?context=1 has an image link in this format: https://www.reddit.com/media?url=https%3A%2F%2Fi.redd.it%2Fpdnxq8dj0w881.jpg
    NSTextCheckingResult *mediaMatch = [MediaShareLinkRegex firstMatchInString:string options:0 range:NSMakeRange(0, [string length])];
    if (mediaMatch) {
        NSRange media = [mediaMatch rangeAtIndex:1];
        NSString *encodedURLString = [string substringWithRange:media];
        NSString *decodedURLString = [encodedURLString stringByRemovingPercentEncoding];
        NSURL *decodedURL = [NSURL URLWithString:decodedURLString];
        return decodedURL;
    }
    return %orig;
}

// Fix Settings -> General -> Open Tweets in
// Rewrite x.com links as twitter.com
- (NSString *)host {
    NSString *originalHost = %orig;
    if ([originalHost isEqualToString:@"x.com"]) {
        return @"twitter.com";
    }
    return originalHost;
}
%end

// Randomise the trending subreddits list
%hook NSBundle
- (NSURL *)URLForResource:(NSString *)name withExtension:(NSString *)ext {
    NSURL *url = %orig;
    if ([name isEqualToString:@"trending-subreddits"] && [ext isEqualToString:@"plist"]) {
        /*
            - Parse plist
            - Select random list of subreddits from the dict
            - Add today's date to the dict, with the list as the value
            - Return plist as a new file
        */
        NSMutableDictionary *dict = [[NSDictionary dictionaryWithContentsOfURL:url] mutableCopy];
        // Select random array from dict
        NSArray *keys = [dict allKeys];
        NSString *randomKey = keys[arc4random_uniform((uint32_t)[keys count])];
        NSArray *array = dict[randomKey];
        // Get string of today's date
        NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
        // ex: 2023-9-28 (28th September 2023)
        [formatter setDateFormat:@"yyyy-M-d"];

        [dict setObject:array forKey:[formatter stringFromDate:[NSDate date]]];

        // write new file
        NSString *tempPath = [NSTemporaryDirectory() stringByAppendingPathComponent:@"trending-custom.plist"];
        [[NSFileManager defaultManager] removeItemAtPath:tempPath error:nil]; // remove in case it exists
        [dict writeToFile:tempPath atomically:YES];

        return [NSURL fileURLWithPath:tempPath];
    }
    return url;
}
%end

// Fix crash issue
// ref: https://github.com/JeffreyCA/Apollo-ImprovedCustomApi/commit/51c72a72fb6ab9b114449202af9ded0f19a03eb4
%hook NSDictionary
%new
- (NSInteger)integerValue {
    return 0;
}
%end
%end // CustomID end

// Add Settings button
static NSInteger sectionCount;
%group SettingsViewController
%hook ApolloSettingsViewController
- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    sectionCount = %orig;
    return sectionCount + 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    if (section == sectionCount) {
        return 1;
    }
    return %orig;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.section == sectionCount) {
        UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"CustomCell"];
        cell.textLabel.text = @"ApolloPatcher";
        cell.textLabel.textAlignment = NSTextAlignmentCenter;
        cell.backgroundColor = COLOR_BACKGROUND;
        cell.textLabel.textColor = [UIColor whiteColor];
        cell.tag = 22377;
        return cell;
    }
    return %orig;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *selectedCell = [tableView cellForRowAtIndexPath:indexPath];
    if (selectedCell.tag == 22377) {
        [tableView deselectRowAtIndexPath:indexPath animated:NO];
        [self performSelector:@selector(settingsButtonPushed) withObject:nil];
    } else {
        %orig;
    }
}

%new
- (void)settingsButtonPushed {
    UINavigationController *settingsVC = [[UINavigationController alloc] initWithRootViewController:[[SettingsController alloc] init]];
    [self presentViewController:settingsVC animated:YES completion:nil];
}
%end

%end // SettingsViewController end

// Sideload fixes
static NSDictionary *stripGroupAccessAttr(CFDictionaryRef attributes) {
    NSMutableDictionary *newAttributes = [[NSMutableDictionary alloc] initWithDictionary:(__bridge id)attributes];
    [newAttributes removeObjectForKey:(__bridge id)kSecAttrAccessGroup];
    return newAttributes;
}

static void *SecItemAdd_orig;
static OSStatus SecItemAdd_replacement(CFDictionaryRef query, CFTypeRef *result) {
    NSDictionary *strippedQuery = stripGroupAccessAttr(query);
    return ((OSStatus (*)(CFDictionaryRef, CFTypeRef *))SecItemAdd_orig)((__bridge CFDictionaryRef)strippedQuery, result);
}

static void *SecItemCopyMatching_orig;
static OSStatus SecItemCopyMatching_replacement(CFDictionaryRef query, CFTypeRef *result) {
    NSDictionary *strippedQuery = stripGroupAccessAttr(query);
    return ((OSStatus (*)(CFDictionaryRef, CFTypeRef *))SecItemCopyMatching_orig)((__bridge CFDictionaryRef)strippedQuery, result);
}

static void *SecItemUpdate_orig;
static OSStatus SecItemUpdate_replacement(CFDictionaryRef query, CFDictionaryRef attributesToUpdate) {
    NSDictionary *strippedQuery = stripGroupAccessAttr(query);
    return ((OSStatus (*)(CFDictionaryRef, CFDictionaryRef))SecItemUpdate_orig)((__bridge CFDictionaryRef)strippedQuery, attributesToUpdate);
}

%ctor {
    @autoreleasepool {
        kCustomID = (id)[[[NSUserDefaults standardUserDefaults] objectForKey:@"Custom_ID"] ?: nil copy];
        kClientID = (id)[[[NSUserDefaults standardUserDefaults] objectForKey:@"IMGUR_ID"] ?: @"8b15a972041abb1" copy];
        // Dystopia method default: user Reddit apps register dystopia://response,
        // which Apollo can't route natively — the CustomOAuth WKWebView flow
        // intercepts that callback instead. Set REDIRECT_URI to override.
        kRedirectURI = (id)[[[NSUserDefaults standardUserDefaults] objectForKey:@"REDIRECT_URI"] ?: @"dystopia://response" copy];
        kUserAgent = (id)[[[NSUserDefaults standardUserDefaults] objectForKey:@"USER_AGENT"] ?: @"ios:com.CarbonDev.Dystopia:v1.0.1(by /u/DystopiaForReddit)" copy];
        // Suppress wallpaper prompt
        NSDate *dateIn90d = [NSDate dateWithTimeIntervalSinceNow:60*60*24*90];
        [[NSUserDefaults standardUserDefaults] setObject:dateIn90d forKey:@"WallpaperPromptMostRecent2"];

        %init(CustomID);
        %init(CustomOAuth, ASWebAuthenticationSession = objc_getClass("ASWebAuthenticationSession"));

        %init(SettingsViewController, ApolloSettingsViewController = objc_getClass("Apollo.SettingsViewController"));
        // Add support for share links (e.g. reddit.com/r/subreddit/s/xxxxxx) in Apollo.
        cache = [NSCache new];
        NSError *error = NULL;
        ShareLinkRegex = [NSRegularExpression regularExpressionWithPattern:ShareLinkRegexPattern options:NSRegularExpressionCaseInsensitive error:&error];
        // Fix Reddit Media URL redirects
        MediaShareLinkRegex = [NSRegularExpression regularExpressionWithPattern:MediaShareLinkPattern options:NSRegularExpressionCaseInsensitive error:&error];

        // Sideload fixes
        rebind_symbols((struct rebinding[3]) {
            {"SecItemAdd", (void *)SecItemAdd_replacement, (void **)&SecItemAdd_orig},
            {"SecItemCopyMatching", (void *)SecItemCopyMatching_replacement, (void **)&SecItemCopyMatching_orig},
            {"SecItemUpdate", (void *)SecItemUpdate_replacement, (void **)&SecItemUpdate_orig}
        }, 3);
    }
}
