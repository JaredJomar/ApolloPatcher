#import "ApolloWebSessionStore.h"

#import <Security/Security.h>

// Local logging shims so this module stays self-contained.
#ifndef ApolloLog
#define ApolloLog(fmt, ...) NSLog(fmt, ##__VA_ARGS__)
#endif
#ifndef ApolloLogDebug
#define ApolloLogDebug(fmt, ...) NSLog(fmt, ##__VA_ARGS__)
#endif

@implementation ApolloWebSessionEntry
@end

#pragma mark - Keychain helpers (local port of Reborn's shared keychain utils)

static NSMutableDictionary *ApolloBaseGenericPasswordDict(CFStringRef service, CFStringRef account) {
    return [NSMutableDictionary dictionaryWithDictionary:@{
        (__bridge NSString *)kSecClass: (__bridge NSString *)kSecClassGenericPassword,
        (__bridge NSString *)kSecAttrService: (__bridge NSString *)service,
        (__bridge NSString *)kSecAttrAccount: (__bridge NSString *)account,
    }];
}

static CFDictionaryRef ApolloCreateGenericPasswordDataQuery(CFStringRef service, CFStringRef account) {
    NSMutableDictionary *query = ApolloBaseGenericPasswordDict(service, account);
    query[(__bridge NSString *)kSecReturnData] = @YES;
    query[(__bridge NSString *)kSecMatchLimit] = (__bridge NSString *)kSecMatchLimitOne;
    return CFBridgingRetain(query);
}

static CFDictionaryRef ApolloCreateGenericPasswordIdentity(CFStringRef service, CFStringRef account) {
    return CFBridgingRetain(ApolloBaseGenericPasswordDict(service, account));
}

static OSStatus ApolloUpsertGenericPasswordData(CFStringRef service, CFStringRef account, NSData *data, CFTypeRef accessible) {
    NSMutableDictionary *add = ApolloBaseGenericPasswordDict(service, account);
    add[(__bridge NSString *)kSecValueData] = data;
    add[(__bridge NSString *)kSecAttrAccessible] = (__bridge NSString *)accessible;
    OSStatus status = SecItemAdd((__bridge CFDictionaryRef)add, NULL);
    if (status == errSecDuplicateItem) {
        NSDictionary *update = @{
            (__bridge NSString *)kSecValueData: data,
            (__bridge NSString *)kSecAttrAccessible: (__bridge NSString *)accessible,
        };
        status = SecItemUpdate((__bridge CFDictionaryRef)add, (__bridge CFDictionaryRef)update);
    }
    return status;
}

#pragma mark - Keychain-backed persistence

static CFStringRef const kWebSessionKeychainService = CFSTR("com.christianselig.Apollo.webjson");

static NSString *ApolloWebSessionKeychainAccountName(NSString *suffix, NSString *username) {
    return [NSString stringWithFormat:@"websession:%@:%@", username, suffix];
}

static NSString *ApolloWebSessionKeychainRead(NSString *account) {
    CFDictionaryRef query =
        ApolloCreateGenericPasswordDataQuery(kWebSessionKeychainService,
                                             (__bridge CFStringRef)account);
    CFTypeRef result = NULL;
    OSStatus st = SecItemCopyMatching(query, &result);
    CFRelease(query);
    if (st != errSecSuccess || !result) {
        if (result) CFRelease(result);
        return nil;
    }
    if (CFGetTypeID(result) != CFDataGetTypeID()) {
        CFRelease(result);
        ApolloLog(@"[WebSessionStore] Keychain read returned a non-data value");
        return nil;
    }
    NSData *data = CFBridgingRelease(result);
    NSString *value = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    return value.length > 0 ? value : nil;
}

static void ApolloWebSessionKeychainWrite(NSString *account, NSString *value) {
    if (value.length == 0) {
        CFDictionaryRef match =
            ApolloCreateGenericPasswordIdentity(kWebSessionKeychainService,
                                                (__bridge CFStringRef)account);
        SecItemDelete(match);
        CFRelease(match);
        return;
    }
    NSData *data = [value dataUsingEncoding:NSUTF8StringEncoding];
    if (!data) {
        ApolloLog(@"[WebSessionStore] Keychain value could not be encoded as UTF-8");
        return;
    }
    OSStatus st =
        ApolloUpsertGenericPasswordData(kWebSessionKeychainService,
                                        (__bridge CFStringRef)account, data,
                                        kSecAttrAccessibleAfterFirstUnlock);
    if (st != errSecSuccess) {
        ApolloLog(@"[WebSessionStore] Keychain write for %@ failed (OSStatus %d)", account, (int)st);
    }
}

static NSString *const kUDKeyWebSessionUsernameIndex = @"WebSessionUsernameIndex";
static NSString *const kUDKeyWebSessionPollOnlyIndex = @"WebSessionPollOnlyIndex";

static NSString *ApolloWebSessionNormalizeUsername(NSString *username) {
    return [[username ?: @"" stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] lowercaseString];
}

static void ApolloWebSessionUpdateIndexNamed(NSString *indexKey, NSString *key, BOOL present) {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSArray<NSString *> *raw = [defaults arrayForKey:indexKey];
    NSMutableSet<NSString *> *set = [NSMutableSet setWithArray:[raw isKindOfClass:[NSArray class]] ? raw : @[]];
    if (present) [set addObject:key]; else [set removeObject:key];
    [defaults setObject:set.allObjects forKey:indexKey];
}

static void ApolloWebSessionUpdateIndex(NSString *key, BOOL present) {
    ApolloWebSessionUpdateIndexNamed(kUDKeyWebSessionUsernameIndex, key, present);
}

static BOOL ApolloWebSessionIndexContains(NSString *indexKey, NSString *key) {
    NSArray<NSString *> *raw = [[NSUserDefaults standardUserDefaults] arrayForKey:indexKey];
    return [raw isKindOfClass:[NSArray class]] && [raw containsObject:key];
}

static BOOL ApolloWebSessionIsPollOnly(NSString *key) {
    return ApolloWebSessionIndexContains(kUDKeyWebSessionPollOnlyIndex, key);
}

static BOOL ApolloWebSessionIsPrimary(NSString *key) {
    return ApolloWebSessionIndexContains(kUDKeyWebSessionUsernameIndex, key);
}

#pragma mark - Public API

static ApolloWebSessionEntry *ApolloWebSessionReadEntry(NSString *key) {
    NSString *cookie = ApolloWebSessionKeychainRead(ApolloWebSessionKeychainAccountName(@"cookie", key));
    if (cookie.length == 0) return nil;
    ApolloWebSessionEntry *entry = [ApolloWebSessionEntry new];
    entry.cookieHeader = cookie;
    entry.modhash = ApolloWebSessionKeychainRead(ApolloWebSessionKeychainAccountName(@"modhash", key)) ?: @"";
    entry.pollOnly = ApolloWebSessionIsPollOnly(key);
    return entry;
}

ApolloWebSessionEntry *ApolloWebSessionFor(NSString *username) {
    NSString *key = ApolloWebSessionNormalizeUsername(username);
    if (key.length == 0) return nil;
    if (ApolloWebSessionIsPollOnly(key)) return nil;
    return ApolloWebSessionReadEntry(key);
}

ApolloWebSessionEntry *ApolloWebSessionPollFor(NSString *username) {
    NSString *key = ApolloWebSessionNormalizeUsername(username);
    if (key.length == 0) return nil;
    return ApolloWebSessionReadEntry(key);
}

void ApolloWebSessionSet(NSString *username, NSString *cookieHeader, NSString *modhash) {
    NSString *key = ApolloWebSessionNormalizeUsername(username);
    if (key.length == 0) return;
    if (cookieHeader.length == 0) { ApolloWebSessionRemove(username); return; }
    ApolloWebSessionKeychainWrite(ApolloWebSessionKeychainAccountName(@"cookie", key), cookieHeader);
    ApolloWebSessionKeychainWrite(ApolloWebSessionKeychainAccountName(@"modhash", key), modhash ?: @"");
    ApolloWebSessionUpdateIndexNamed(kUDKeyWebSessionPollOnlyIndex, key, NO);
    ApolloWebSessionUpdateIndex(key, YES);
    ApolloLogDebug(@"[WebSessionStore] Stored web session for u/%@ (%lu cookie bytes, modhash %@)",
                   username, (unsigned long)cookieHeader.length, modhash.length > 0 ? @"present" : @"absent");
}

void ApolloWebSessionSetPollOnly(NSString *username, NSString *cookieHeader, NSString *modhash) {
    NSString *key = ApolloWebSessionNormalizeUsername(username);
    if (key.length == 0) return;
    if (cookieHeader.length == 0) return;
    if (ApolloWebSessionIsPrimary(key) || ApolloWebSessionFor(username)) {
        ApolloWebSessionSet(username, cookieHeader, modhash);
        return;
    }
    ApolloWebSessionKeychainWrite(ApolloWebSessionKeychainAccountName(@"cookie", key), cookieHeader);
    ApolloWebSessionKeychainWrite(ApolloWebSessionKeychainAccountName(@"modhash", key), modhash ?: @"");
    ApolloWebSessionUpdateIndex(key, NO);
    ApolloWebSessionUpdateIndexNamed(kUDKeyWebSessionPollOnlyIndex, key, YES);
    ApolloLogDebug(@"[WebSessionStore] Stored poll-only web session for u/%@ (%lu cookie bytes, modhash %@)",
                   username, (unsigned long)cookieHeader.length, modhash.length > 0 ? @"present" : @"absent");
}

void ApolloWebSessionRemove(NSString *username) {
    NSString *key = ApolloWebSessionNormalizeUsername(username);
    if (key.length == 0) return;
    ApolloWebSessionKeychainWrite(ApolloWebSessionKeychainAccountName(@"cookie", key), nil);
    ApolloWebSessionKeychainWrite(ApolloWebSessionKeychainAccountName(@"modhash", key), nil);
    ApolloWebSessionUpdateIndex(key, NO);
    ApolloWebSessionUpdateIndexNamed(kUDKeyWebSessionPollOnlyIndex, key, NO);
    ApolloLog(@"[WebSessionStore] Removed web session for u/%@", username);
}

NSSet<NSString *> *ApolloWebSessionUsernames(void) {
    NSArray<NSString *> *raw = [[NSUserDefaults standardUserDefaults] arrayForKey:kUDKeyWebSessionUsernameIndex];
    return [NSSet setWithArray:[raw isKindOfClass:[NSArray class]] ? raw : @[]];
}

#pragma mark - Active account resolution

// Local port of Reborn's ApolloActiveAccountUsername(): resolves purely from
// the on-disk RedditAccounts2/CurrentRedditAccountIndex blobs (group suite),
// which is correct from the very first %ctor call onward.
static NSString * const kWebSessionGroupSuite = @"group.com.christianselig.apollo";

static id ApolloWebSessionUnarchive(NSData *data) {
    if (![data isKindOfClass:[NSData class]]) return nil;
    NSError *e = nil;
    NSKeyedUnarchiver *u = [[NSKeyedUnarchiver alloc] initForReadingFromData:data error:&e];
    if (!u) return nil;
    u.requiresSecureCoding = NO;
    id obj = nil;
    @try { obj = [u decodeTopLevelObjectForKey:NSKeyedArchiveRootObjectKey error:&e]; }
    @catch (__unused NSException *ex) { obj = nil; }
    [u finishDecoding];
    return obj;
}

static NSString *ApolloActiveAccountUsername(void) {
    NSUserDefaults *group = [[NSUserDefaults alloc] initWithSuiteName:kWebSessionGroupSuite];
    id accountsObj = ApolloWebSessionUnarchive([group objectForKey:@"RedditAccounts2"]);
    NSArray *accounts = [accountsObj isKindOfClass:[NSArray class]] ? accountsObj : nil;
    if (!accounts.count) return nil;
    NSInteger index = [group integerForKey:@"CurrentRedditAccountIndex"];
    if (index < 0 || (NSUInteger)index >= accounts.count) return nil;
    id client = accounts[index];
    if (!client) return nil;
    id user = nil;
    @try { user = [client valueForKey:@"currentUser"]; }
    @catch (__unused NSException *e) { return nil; }
    NSString *username = nil;
    @try { username = [user valueForKey:@"username"]; }
    @catch (__unused NSException *e) { return nil; }
    return [username isKindOfClass:[NSString class]] && username.length > 0 ? username.lowercaseString : nil;
}

NSString *ApolloActiveWebSessionUsername(void) {
    return ApolloActiveAccountUsername();
}

ApolloWebSessionEntry *ApolloActiveWebSession(void) {
    NSString *username = ApolloActiveWebSessionUsername();
    if (username.length == 0) return nil;
    return ApolloWebSessionFor(username);
}
