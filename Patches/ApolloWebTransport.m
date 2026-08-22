#import "ApolloWebTransport.h"

#import "ApolloWebSessionStore.h"

#ifndef ApolloLog
#define ApolloLog(fmt, ...) NSLog(fmt, ##__VA_ARGS__)
#endif

static NSString * const kWebTransportFlagKey = @"WEB_TRANSPORT_ENABLED";

// Browser-grade UA so www.reddit.com serves the same treatment the website gets
// (same rationale as the RedGIFs swap: old app UAs get gated/muted variants).
static NSString * const kWebTransportBrowserUA =
    @"Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 "
    @"(KHTML, like Gecko) Version/17.5 Safari/605.1.15";

BOOL ApolloWebTransportEnabled(void) {
    return [[NSUserDefaults standardUserDefaults] boolForKey:kWebTransportFlagKey];
}

NSURLRequest *ApolloWebTransportRewriteRequest(NSURLRequest *request) {
    if (!request) return nil;

    NSString *username = ApolloActiveWebSessionUsername();
    if (username.length == 0) return nil;
    ApolloWebSessionEntry *session = ApolloWebSessionFor(username);
    if (session.cookieHeader.length == 0) return nil;

    NSURL *url = request.URL;
    NSString *host = url.host.lowercaseString;
    // Reads-only phase: only hijack the OAuth API host. www.reddit.com traffic
    // already behaves like the web.
    if (![host isEqualToString:@"oauth.reddit.com"]) return nil;

    NSString *path = url.path ?: @"/";
    // Identity/token endpoints have different body shapes per host — never touch.
    if ([path hasPrefix:@"/api/v1/"]) return nil;

    NSString *method = request.HTTPMethod.uppercaseString ?: @"GET";
    BOOL isWrite = !([method isEqualToString:@"GET"] || [method isEqualToString:@"HEAD"]);
    // Writes need modhash-aware handling and routable-path whitelisting; keep
    // them on the OAuth path until that layer is ported.
    if (isWrite) return nil;

    NSURLComponents *components = [NSURLComponents componentsWithURL:url resolvingAgainstBaseURL:NO];
    if (!components) return nil;
    components.host = @"www.reddit.com";

    // Listing/page URLs must carry ".json"; /api endpoints are already JSON.
    NSString *p = components.path ?: @"/";
    if (![p hasSuffix:@".json"]) {
        while ([p hasSuffix:@"/"] && p.length > 1) p = [p substringToIndex:p.length - 1];
        components.path = [p isEqualToString:@"/"] ? @"/.json" : [p stringByAppendingString:@".json"];
    }

    // raw_json=1 keeps bodies close to the API shape Apollo expects.
    NSMutableArray<NSURLQueryItem *> *items =
        [[NSMutableArray alloc] initWithArray:components.queryItems ?: @[]];
    BOOL hasRawJson = NO;
    for (NSURLQueryItem *item in items) {
        if ([item.name isEqualToString:@"raw_json"]) { hasRawJson = YES; break; }
    }
    if (!hasRawJson) [items addObject:[NSURLQueryItem queryItemWithName:@"raw_json" value:@"1"]];
    components.queryItems = items;

    NSURL *rewrittenURL = components.URL;
    if (!rewrittenURL) return nil;

    NSMutableURLRequest *rewritten = [request mutableCopy];
    rewritten.URL = rewrittenURL;
    [rewritten setValue:nil forHTTPHeaderField:@"Authorization"];
    [rewritten setValue:session.cookieHeader forHTTPHeaderField:@"Cookie"];
    rewritten.HTTPShouldHandleCookies = NO;
    [rewritten setValue:kWebTransportBrowserUA forHTTPHeaderField:@"User-Agent"];

    ApolloLog(@"[WebTransport] %@ %@ -> u/%@ session", method, path, username);
    return rewritten;
}
