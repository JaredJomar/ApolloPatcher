#import "ApolloWebAuthViewController.h"

#import <WebKit/WebKit.h>

#import "ApolloWebSessionStore.h"

@interface ApolloWebAuthViewController () <WKNavigationDelegate>
@property (nonatomic, strong) WKWebView *webView;
@property (nonatomic, strong) UIActivityIndicatorView *spinner;
@property (nonatomic, copy) NSURL *authURL;
@property (nonatomic, copy) NSString *redirectURIString;
@property (nonatomic, copy) NSURL *redirectURL;
@property (nonatomic, copy) void (^completion)(NSURL *, NSError *);
@property (nonatomic) BOOL finished;
@end

@implementation ApolloWebAuthViewController

- (instancetype)initWithURL:(NSURL *)url
                redirectURI:(NSString *)redirectURI
          completionHandler:(void (^)(NSURL *, NSError *))completion {
    self = [super init];
    if (self) {
        _authURL = [url copy];
        _redirectURIString = [redirectURI copy];
        _redirectURL = [NSURL URLWithString:redirectURI];
        _completion = [completion copy];
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Sign In to Reddit";
    self.view.backgroundColor = [UIColor whiteColor];

    self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc]
        initWithBarButtonSystemItem:UIBarButtonSystemItemCancel
                             target:self
                             action:@selector(_cancelTapped)];

    // iOS 15 and earlier can't render the modern Reddit login page.
    // Rewrite www.reddit.com → old.reddit.com before the first load.
    if (![self _isModernRedditSupported]) {
        NSLog(@"ApolloPatcher:[WebAuth] iOS < 16 detected — auto-switching to old.reddit.com");
        self.authURL = [self _rewriteToOldReddit:self.authURL];
    }

    // Non-persistent data store mirrors Apollo's prefersEphemeralWebBrowserSession = YES
    WKWebViewConfiguration *config = [[WKWebViewConfiguration alloc] init];
    config.websiteDataStore = [WKWebsiteDataStore nonPersistentDataStore];

    self.webView = [[WKWebView alloc] initWithFrame:self.view.bounds configuration:config];
    self.webView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.webView.navigationDelegate = self;
    [self.view addSubview:self.webView];

    self.spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleGray];
    self.spinner.autoresizingMask = UIViewAutoresizingFlexibleTopMargin | UIViewAutoresizingFlexibleBottomMargin |
                                    UIViewAutoresizingFlexibleLeftMargin  | UIViewAutoresizingFlexibleRightMargin;
    self.spinner.center = self.view.center;
    [self.view addSubview:self.spinner];
    [self.spinner startAnimating];

    NSLog(@"ApolloPatcher:[WebAuth] Loading auth URL: %@", self.authURL);
    [self.webView loadRequest:[NSURLRequest requestWithURL:self.authURL]];
}

- (BOOL)_isModernRedditSupported {
    if (@available(iOS 16, *)) return YES;
    return NO;
}

- (NSURL *)_rewriteToOldReddit:(NSURL *)url {
    NSURLComponents *c = [NSURLComponents componentsWithURL:url resolvingAgainstBaseURL:NO];
    if ([c.host isEqualToString:@"www.reddit.com"] || [c.host isEqualToString:@"reddit.com"]) {
        c.host = @"old.reddit.com";
    }
    return c.URL ?: url;
}

- (void)_cancelTapped {
    NSLog(@"ApolloPatcher:[WebAuth] User cancelled sign-in");
    [self _finishWithURL:nil
                   error:[NSError errorWithDomain:@"ASWebAuthenticationSessionErrorDomain"
                                            code:1
                                        userInfo:nil]];
}

- (void)_finishWithURL:(NSURL *)url error:(NSError *)error {
    if (self.finished) return;
    self.finished = YES;
    void (^completion)(NSURL *, NSError *) = self.completion;
    [self.navigationController dismissViewControllerAnimated:YES completion:^{
        if (completion) completion(url, error);
    }];
}

#pragma mark - Web session harvest (Reborn-style cookie capture)

// Before tearing the ephemeral WKWebView down, grab every reddit.com cookie
// and persist them as the account's web session (Reborn-style). Identity comes
// from a lightweight /api/me.json call carrying the harvested cookie header.
- (void)_harvestAndFinishWithURL:(NSURL *)url {
    WKWebsiteDataStore *store = self.webView.configuration.websiteDataStore;
    [[store httpCookieStore] getAllCookies:^(NSArray<NSHTTPCookie *> *cookies) {
        NSMutableString *header = [NSMutableString string];
        for (NSHTTPCookie *cookie in cookies) {
            if ([cookie.domain containsString:@"reddit.com"]) {
                if (header.length > 0) [header appendString:@"; "];
                [header appendFormat:@"%@=%@", cookie.name, cookie.value];
            }
        }
        if (header.length > 0) {
            [self _storeCookieHeader:header];
        } else {
            NSLog(@"ApolloPatcher:[WebAuth] no reddit.com cookies found to harvest");
        }
        [self _finishWithURL:url error:nil];
    }];
}

- (void)_storeCookieHeader:(NSString *)header {
    NSMutableURLRequest *request = [[NSMutableURLRequest alloc]
        initWithURL:[NSURL URLWithString:@"https://www.reddit.com/api/me.json"]
        cachePolicy:NSURLRequestReloadIgnoringLocalCacheData
        timeoutInterval:15.0];
    [request setValue:header forHTTPHeaderField:@"Cookie"];
    [[[NSURLSession sharedSession] dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        NSString *username = nil;
        NSString *modhash = nil;
        if (!error && data) {
            id json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
            if ([json isKindOfClass:[NSDictionary class]]) {
                id payload = json[@"data"];
                if ([payload isKindOfClass:[NSDictionary class]]) {
                    id name = payload[@"name"];
                    if ([name isKindOfClass:[NSString class]] && [(NSString *)name length] > 0) {
                        username = name;
                    }
                    id mh = payload[@"modhash"];
                    if ([mh isKindOfClass:[NSString class]] && [(NSString *)mh length] > 0) {
                        modhash = mh;
                    }
                }
            }
        }
        if (username) {
            ApolloWebSessionSet(username, header, modhash);
            NSLog(@"ApolloPatcher:[WebAuth] stored web session for u/%@ (%lu cookie bytes)",
                  username, (unsigned long)header.length);
        } else {
            NSLog(@"ApolloPatcher:[WebAuth] harvested cookies but identity unresolved (error=%@)", error);
        }
    }] resume];
}

#pragma mark - WKNavigationDelegate

// Matches scheme + host + path against our configured redirect URI, ignoring
// query and fragment (Reddit appends ?state=&code= or ?error= to the URI).
// Matching the full URI — not just the scheme — is what lets http/https redirect
// URIs (Reddit "Web app" API clients) work: every Reddit page navigation shares
// the same https scheme, so scheme-only matching would fire on the wrong page.
- (BOOL)_isCallbackURL:(NSURL *)url {
    if (!self.redirectURL || !url) return NO;

    if ([url.scheme caseInsensitiveCompare:self.redirectURL.scheme] != NSOrderedSame) {
        return NO;
    }

    // Custom schemes (e.g. apollo://reddit-oauth) typically have no host/path
    // beyond the scheme itself — in that case scheme matching alone is already
    // unambiguous.
    NSString *redirectHost = self.redirectURL.host;
    if (redirectHost.length > 0) {
        if ([url.host caseInsensitiveCompare:redirectHost] != NSOrderedSame) {
            return NO;
        }
        NSString *redirectPath = self.redirectURL.path ?: @"";
        NSString *urlPath = url.path ?: @"";
        if (![urlPath isEqualToString:redirectPath]) {
            return NO;
        }
    }

    return YES;
}

- (void)webView:(WKWebView *)webView
decidePolicyForNavigationAction:(WKNavigationAction *)navigationAction
decisionHandler:(void (^)(WKNavigationActionPolicy))decisionHandler {
    NSURL *url = navigationAction.request.URL;

    if ([self _isCallbackURL:url]) {
        // Reddit redirected to our callback URI — intercept before the OS tries
        // to dispatch it (which would fail for unregistered schemes) or the
        // request actually goes out over the network (for http/https redirects).
        decisionHandler(WKNavigationActionPolicyCancel);
        NSLog(@"ApolloPatcher:[WebAuth] Intercepted callback: %@", url);
        [self _harvestAndFinishWithURL:url];
        return;
    }

    // On iOS < 16 the modern Reddit web app fails to render. After the user
    // logs in on old.reddit.com, Reddit's server redirects to
    // www.reddit.com/api/v1/authorize (the consent page) via the `dest` query
    // param — which is also the modern app and also fails. Intercept any
    // mid-flow navigation to www.reddit.com and rewrite to old.reddit.com so
    // the entire OAuth flow stays on old Reddit.
    if (![self _isModernRedditSupported]) {
        NSURL *rewritten = [self _rewriteToOldReddit:url];
        if (![rewritten isEqual:url]) {
            decisionHandler(WKNavigationActionPolicyCancel);
            NSLog(@"ApolloPatcher:[WebAuth] Rewriting mid-flow www.reddit.com → old.reddit.com: %@", rewritten);
            [self.webView loadRequest:[NSURLRequest requestWithURL:rewritten]];
            return;
        }
    }

    decisionHandler(WKNavigationActionPolicyAllow);
}

- (void)webView:(WKWebView *)webView didStartProvisionalNavigation:(WKNavigation *)navigation {
    [self.spinner startAnimating];
}

- (void)webView:(WKWebView *)webView didFinishNavigation:(WKNavigation *)navigation {
    [self.spinner stopAnimating];
}

- (void)webView:(WKWebView *)webView didFailProvisionalNavigation:(WKNavigation *)navigation withError:(NSError *)error {
    [self.spinner stopAnimating];
    // NSURLErrorCancelled (-999): fired by our own decisionHandler cancel.
    // WebKitErrorDomain 102 (WebKitErrorFrameLoadInterruptedByPolicyChange): also
    // fired when decidePolicyForNavigationAction cancels a navigation — expected.
    if (error.code == NSURLErrorCancelled) return;
    if ([error.domain isEqualToString:@"WebKitErrorDomain"] && error.code == 102) return;
    NSLog(@"ApolloPatcher:[WebAuth] Provisional navigation failed: %@", error);
    [self _finishWithURL:nil error:error];
}

- (void)webView:(WKWebView *)webView didFailNavigation:(WKNavigation *)navigation withError:(NSError *)error {
    [self.spinner stopAnimating];
    if (error.code == NSURLErrorCancelled) return;
    NSLog(@"ApolloPatcher:[WebAuth] Navigation failed: %@", error);
    [self _finishWithURL:nil error:error];
}

@end