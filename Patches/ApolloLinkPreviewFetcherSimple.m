// ApolloLinkPreviewFetcherSimple.m
//
// Simplified fetcher for link preview metadata.
// Supports: Open Graph, Twitter Card, Reddit API (user/subreddit), trusted hosts.

#import "ApolloLinkPreviewFetcherSimple.h"
#import "ApolloLinkPreviewModelSimple.h"

#import <CommonCrypto/CommonDigest.h>

static NSString *const kUserAgent = @"ApolloPatcher/0.1.1 (+https://github.com/ichitaso/ApolloPatcher)";

@interface ApolloLinkPreviewFetcherSimple ()

@property (nonatomic, strong) NSURLSession *session;
@property (nonatomic, strong) NSMutableDictionary<NSURL *, ApolloLinkPreviewFetchCompletion> *pendingCompletions;

@end

@implementation ApolloLinkPreviewFetcherSimple

+ (instancetype)sharedFetcher {
    static ApolloLinkPreviewFetcherSimple *fetcher = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ fetcher = [[self alloc] init]; });
    return fetcher;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        NSURLSessionConfiguration *config = [NSURLSessionConfiguration ephemeralSessionConfiguration];
        config.timeoutIntervalForRequest = 10.0;
        config.timeoutIntervalForResource = 20.0;
        config.requestCachePolicy = NSURLRequestReloadIgnoringLocalCacheData;
        config.HTTPAdditionalHeaders = @{@"User-Agent": kUserAgent};
        _session = [NSURLSession sessionWithConfiguration:config delegate:nil delegateQueue:nil];
        _pendingCompletions = [NSMutableDictionary new];
        NSLog(@"ApolloPatcher:[LinkPreviews] fetcher init");
    }
    return self;
}

- (void)fetchPreviewForURL:(NSURL *)url completion:(ApolloLinkPreviewFetchCompletion)completion {
    if (!url || !completion) {
        completion(nil, [NSError errorWithDomain:@"ApolloLinkPreview" code:-1 userInfo:@{NSLocalizedDescriptionKey: @"Invalid URL"}]);
        return;
    }

    // Check if we're already fetching this URL
    if ([self.pendingCompletions objectForKey:url]) {
        // Could queue multiple completions, but for simplicity just reject
        completion(nil, [NSError errorWithDomain:@"ApolloLinkPreview" code:-2 userInfo:@{NSLocalizedDescriptionKey: @"Fetch already in progress"}]);
        return;
    }

    [self.pendingCompletions setObject:completion forKey:url];

    // Check for Reddit user/subreddit first (special handling)
    if ([self isRedditUserProfileURL:url]) {
        [self fetchRedditUserProfile:url completion:completion];
        return;
    }
    if ([self isRedditSubredditURL:url]) {
        [self fetchRedditSubreddit:url completion:completion];
        return;
    }

    // Generic fetch: Open Graph / Twitter Card
    [self fetchGenericPreview:url completion:completion];
}

- (void)finishFetch:(NSURL *)url withPreview:(ApolloLinkPreviewModelSimple * _Nullable)preview error:(NSError * _Nullable)error {
    ApolloLinkPreviewFetchCompletion completion = [self.pendingCompletions objectForKey:url];
    [self.pendingCompletions removeObjectForKey:url];
    if (completion) completion(preview, error);
}

#pragma mark - Reddit API

- (BOOL)isRedditUserProfileURL:(NSURL *)url {
    NSString *host = [url.host lowercaseString] ?: @"";
    if (![host isEqualToString:@"reddit.com"] && ![host hasSuffix:@".reddit.com"]) return NO;
    NSArray *parts = [url.path componentsSeparatedByString:@"/"];
    NSMutableArray *clean = [NSMutableArray array];
    for (NSString *p in parts) if (p.length) [clean addObject:p];
    if (clean.count < 2) return NO;
    NSString *prefix = [clean[0] lowercaseString];
    return [prefix isEqualToString:@"user"] || [prefix isEqualToString:@"u"];
}

- (BOOL)isRedditSubredditURL:(NSURL *)url {
    NSString *host = [url.host lowercaseString] ?: @"";
    if (![host isEqualToString:@"reddit.com"] && ![host hasSuffix:@".reddit.com"]) return NO;
    NSArray *parts = [url.path componentsSeparatedByString:@"/"];
    NSMutableArray *clean = [NSMutableArray array];
    for (NSString *p in parts) if (p.length) [clean addObject:p];
    if (clean.count < 2) return NO;
    NSString *prefix = [clean[0] lowercaseString];
    return [prefix isEqualToString:@"r"];
}

- (void)fetchRedditUserProfile:(NSURL *)url completion:(ApolloLinkPreviewFetchCompletion)completion {
    NSArray *parts = [url.path componentsSeparatedByString:@"/"];
    NSMutableArray *clean = [NSMutableArray array];
    for (NSString *p in parts) if (p.length) [clean addObject:p];
    if (clean.count < 2) { completion(nil, nil); return; }
    NSString *username = [clean[1] stringByRemovingPercentEncoding] ?: clean[1];
    NSString *apiURL = [NSString stringWithFormat:@"https://www.reddit.com/api/info.json?user=%@", username];
    [self performGET:apiURL completion:^(NSData *data, NSError *error) {
        if (error || !data) { completion(nil, error); return; }
        NSError *jsonError = nil;
        id json = [NSJSONSerialization JSONObjectWithData:data options:0 error:&jsonError];
        if (jsonError || !json) { completion(nil, jsonError); return; }
        NSArray *children = json[@"data"][@"children"];
        if (!children || children.count == 0) { completion(nil, nil); return; }
        NSDictionary *dataDict = children[0][@"data"];
        NSString *name = dataDict[@"name"] ?: @"";
        NSString *title = dataDict[@"subreddit"][@"display_name_prefixed"] ?: [@"u/" stringByAppendingString:name];
        NSString *desc = dataDict[@"description"] ?: @"";
        NSString *icon = dataDict[@"icon_img"] ?: dataDict[@"icon_img"] ?: @"";
        NSURL *iconURL = [NSURL URLWithString:icon];
        NSString *banner = dataDict[@"banner_img"] ?: @"";
        NSURL *bannerURL = [NSURL URLWithString:banner];
        NSNumber *subscribers = dataDict[@"subscribers"];
        ApolloLinkPreviewModelSimple *preview = [[ApolloLinkPreviewModelSimple alloc] initWithURL:url
                                                                                               title:title
                                                                                                desc:desc
                                                                                            imageURL:bannerURL ?: iconURL
                                                                                          faviconURL:iconURL
                                                                                            siteName:[@"u/" stringByAppendingString:name]];
        completion(preview, nil);
    }];
}

- (void)fetchRedditSubreddit:(NSURL *)url completion:(ApolloLinkPreviewFetchCompletion)completion {
    NSArray *parts = [url.path componentsSeparatedByString:@"/"];
    NSMutableArray *clean = [NSMutableArray array];
    for (NSString *p in parts) if (p.length) [clean addObject:p];
    if (clean.count < 2) { completion(nil, nil); return; }
    NSString *subreddit = [clean[1] stringByRemovingPercentEncoding] ?: clean[1];
    NSString *apiURL = [NSString stringWithFormat:@"https://www.reddit.com/r/%@/about.json", subreddit];
    [self performGET:apiURL completion:^(NSData *data, NSError *error) {
        if (error || !data) { completion(nil, error); return; }
        NSError *jsonError = nil;
        id json = [NSJSONSerialization JSONObjectWithData:data options:0 error:&jsonError];
        if (jsonError || !json) { completion(nil, jsonError); return; }
        NSDictionary *dataDict = json[@"data"];
        NSString *title = dataDict[@"display_name_prefixed"] ?: [@"r/" stringByAppendingString:subreddit];
        NSString *desc = dataDict[@"public_description"] ?: dataDict[@"description"] ?: @"";
        NSString *icon = dataDict[@"icon_img"] ?: dataDict[@"community_icon"] ?: @"";
        NSURL *iconURL = [NSURL URLWithString:icon];
        NSString *banner = dataDict[@"banner_background_image"] ?: dataDict[@"banner_img"] ?: @"";
        NSURL *bannerURL = [NSURL URLWithString:banner];
        NSNumber *subscribers = dataDict[@"subscribers"];
        ApolloLinkPreviewModelSimple *preview = [[ApolloLinkPreviewModelSimple alloc] initWithURL:url
                                                                                               title:title
                                                                                                desc:desc
                                                                                            imageURL:bannerURL ?: iconURL
                                                                                          faviconURL:iconURL
                                                                                            siteName:[@"r/" stringByAppendingString:subreddit]];
        completion(preview, nil);
    }];
}

#pragma mark - Generic Fetch (Open Graph / Twitter Card)

- (void)fetchGenericPreview:(NSURL *)url completion:(ApolloLinkPreviewFetchCompletion)completion {
    [self performGET:url.absoluteString completion:^(NSData *data, NSError *error) {
        if (error || !data) {
            completion(nil, error);
            return;
        }
        NSString *html = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
        if (!html) { completion(nil, nil); return; }

        NSString *title = [self extractMeta:html property:@"og:title"] ?:
                          [self extractMeta:html name:@"twitter:title"] ?:
                          [self extractTitle:html];
        NSString *desc = [self extractMeta:html property:@"og:description"] ?:
                         [self extractMeta:html name:@"twitter:description"] ?:
                         [self extractMeta:html name:@"description"];
        NSString *image = [self extractMeta:html property:@"og:image"] ?:
                          [self extractMeta:html name:@"twitter:image"];
        NSString *siteName = [self extractMeta:html property:@"og:site_name"];
        NSString *favicon = [self extractFavicon:html];

        NSURL *imageURL = image ? [NSURL URLWithString:image] : nil;
        NSURL *faviconURL = favicon ? [NSURL URLWithString:favicon] : nil;
        if (imageURL && !imageURL.scheme) imageURL = [NSURL URLWithString:[imageURL absoluteString]]; // relative
        if (faviconURL && !faviconURL.scheme) faviconURL = [NSURL URLWithString:[faviconURL absoluteString]];

        ApolloLinkPreviewModelSimple *preview = [[ApolloLinkPreviewModelSimple alloc] initWithURL:url
                                                                                               title:title ?: @""
                                                                                                desc:desc ?: @""
                                                                                            imageURL:imageURL
                                                                                          faviconURL:faviconURL
                                                                                            siteName:siteName ?: @""];
        completion(preview, nil);
    }];
}

- (void)performGET:(NSString *)urlString completion:(void (^)(NSData * _Nullable, NSError * _Nullable))completion {
    NSURL *url = [NSURL URLWithString:urlString];
    if (!url) { completion(nil, [NSError errorWithDomain:@"ApolloLinkPreview" code:-1 userInfo:nil]); return; }
    NSURLRequest *req = [NSURLRequest requestWithURL:url cachePolicy:NSURLRequestReloadIgnoringLocalCacheData timeoutInterval:10.0];
    [self.session dataTaskWithRequest:req completionHandler:^(NSData * _Nullable data, NSURLResponse * _Nullable response, NSError * _Nullable error) {
        if (error) { completion(nil, error); return; }
        NSHTTPURLResponse *http = (NSHTTPURLResponse *)response;
        if (http.statusCode >= 400) { completion(nil, [NSError errorWithDomain:@"ApolloLinkPreview" code:http.statusCode userInfo:nil]); return; }
        completion(data, nil);
    }].resume();
}

#pragma mark - HTML Parsing Helpers

- (NSString *)extractMeta:(NSString *)html property:(NSString *)property {
    NSString *pattern = [NSString stringWithFormat:@"<meta\\s+property=[\"']%@[\"']\\s+content=[\"']([^\"']+)[\"']", [NSRegularExpression escapedPatternForString:property]];
    return [self firstMatch:html pattern:pattern];
}

- (NSString *)extractMeta:(NSString *)html name:(NSString *)name {
    NSString *pattern = [NSString stringWithFormat:@"<meta\\s+name=[\"']%@[\"']\\s+content=[\"']([^\"']+)[\"']", [NSRegularExpression escapedPatternForString:name]];
    return [self firstMatch:html pattern:pattern];
}

- (NSString *)extractTitle:(NSString *)html {
    NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:@"<title>([^<]+)</title>" options:NSRegularExpressionCaseInsensitive error:nil];
    NSTextCheckingResult *match = [regex firstMatchInString:html options:0 range:NSMakeRange(0, html.length)];
    if (match && match.numberOfRanges > 1) return [html substringWithRange:[match rangeAtIndex:1]];
    return nil;
}

- (NSString *)extractFavicon:(NSString *)html {
    // Try rel="icon" first
    NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:@"<link\\s+rel=[\"'](?:shortcut\\s+)?icon[\"']\\s+href=[\"']([^\"']+)[\"']" options:NSRegularExpressionCaseInsensitive error:nil];
    NSTextCheckingResult *match = [regex firstMatchInString:html options:0 range:NSMakeRange(0, html.length)];
    if (match && match.numberOfRanges > 1) return [html substringWithRange:[match rangeAtIndex:1]];
    // Fallback: /favicon.ico
    return @"/favicon.ico";
}

- (NSString *)firstMatch:(NSString *)string pattern:(NSString *)pattern {
    NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:pattern options:NSRegularExpressionCaseInsensitive error:nil];
    NSTextCheckingResult *match = [regex firstMatchInString:string options:0 range:NSMakeRange(0, string.length)];
    if (match && match.numberOfRanges > 1) return [string substringWithRange:[match rangeAtIndex:1]];
    return nil;
}

@end