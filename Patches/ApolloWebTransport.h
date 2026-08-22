#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

#ifdef __cplusplus
extern "C" {
#endif

// YES when the user enabled cookie-based transport for Reddit READ requests.
// Read live from defaults on every call, so toggling takes effect immediately.
BOOL ApolloWebTransportEnabled(void);

// Rewrites an oauth.reddit.com GET into a cookie-authenticated www.reddit.com
// .json request using the active account's harvested web session (Reborn-style).
// Returns nil when disabled, no session, non-oauth host, identity/auth paths,
// or write methods — callers must fall through to the stock path then.
NSURLRequest * _Nullable ApolloWebTransportRewriteRequest(NSURLRequest *request);

#ifdef __cplusplus
}
#endif

NS_ASSUME_NONNULL_END
