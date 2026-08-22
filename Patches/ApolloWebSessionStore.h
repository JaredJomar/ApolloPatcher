#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

// Per-account Web JSON (API-Key-Free) session store (ported from Apollo-Reborn).
//
// Makes the harvested cookie session a per-account property, keyed by
// lowercased Reddit username, mirroring the shape of ApolloAccountCredentials.
// An account either has a web-session entry here (cookie auth) or doesn't
// (OAuth) — "is this a web-session account?" is `ApolloWebSessionFor(u) != nil`.
//
// The session is sensitive (it IS the account's live login), so it's kept in
// the keychain under service string "com.christianselig.Apollo.webjson".

@interface ApolloWebSessionEntry : NSObject
@property (nonatomic, copy) NSString *cookieHeader;
@property (nonatomic, copy) NSString *modhash;
// YES when this session was harvested only for Reddit web features while the
// account still authenticates through OAuth. An auxiliary session is invisible
// to ApolloWebSessionFor / ApolloActiveWebSession (the transport spine); web
// features read it via ApolloWebSessionPollFor.
@property (nonatomic) BOOL pollOnly;
@end

#ifdef __cplusplus
extern "C" {
#endif

// PRIMARY (transport) web session for `username`, or nil. Poll-only sessions
// are intentionally NOT returned here.
ApolloWebSessionEntry * _Nullable ApolloWebSessionFor(NSString *username);

// Any stored web session for `username`, primary or auxiliary.
ApolloWebSessionEntry * _Nullable ApolloWebSessionPollFor(NSString *username);

// Upserts the PRIMARY harvested session for `username`. Empty cookieHeader
// removes the session.
void ApolloWebSessionSet(NSString *username, NSString *_Nullable cookieHeader, NSString *_Nullable modhash);

// Upserts a poll-only session; never downgrades an existing primary session.
void ApolloWebSessionSetPollOnly(NSString *username, NSString *_Nullable cookieHeader, NSString *_Nullable modhash);

void ApolloWebSessionRemove(NSString *username);

NSSet<NSString *> *ApolloWebSessionUsernames(void);

ApolloWebSessionEntry * _Nullable ApolloActiveWebSession(void);

NSString * _Nullable ApolloActiveWebSessionUsername(void);

#ifdef __cplusplus
}
#endif

NS_ASSUME_NONNULL_END
