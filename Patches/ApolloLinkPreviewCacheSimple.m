// ApolloLinkPreviewCacheSimple.m
//
// Simplified in-memory cache for link previews with TTL per host.
// No disk persistence — pure NSCache with timestamp-based eviction.

#import "ApolloLinkPreviewCacheSimple.h"
#import "ApolloLinkPreviewModelSimple.h"

#import <CommonCrypto/CommonDigest.h>

static const NSUInteger kMaxEntries = 500;
static const NSTimeInterval kDefaultTTL = 7.0 * 24.0 * 60.0 * 60.0;   // 7 days
static const NSTimeInterval kRedditTTL = 24.0 * 60.0 * 60.0;          // 1 day
static const NSTimeInterval kYouTubeTTL = 30.0 * 24.0 * 60.0 * 60.0;  // 30 days

@interface ApolloLinkPreviewCacheSimple ()

@property (nonatomic, strong) NSCache<NSString *, ApolloLinkPreviewModelSimple *> *memoryCache;
@property (nonatomic, strong) NSCache<NSString *, NSNumber *> *missCache;
@property (nonatomic, strong) NSCache<NSString *, NSString *> *keyCache;
@property (nonatomic, strong) dispatch_queue_t queue;

@end

@implementation ApolloLinkPreviewCacheSimple

+ (instancetype)sharedCache {
    static ApolloLinkPreviewCacheSimple *cache = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ cache = [[self alloc] init]; });
    return cache;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _queue = dispatch_queue_create("com.apollopatcher.linkpreviews.cache", DISPATCH_QUEUE_SERIAL);
        _memoryCache = [NSCache new];
        _memoryCache.countLimit = kMaxEntries;
        _missCache = [NSCache new];
        _missCache.countLimit = 1024;
        _keyCache = [NSCache new];
        _keyCache.countLimit = 1024;
        NSLog(@"ApolloPatcher:[LinkPreviews] cache init");
    }
    return self;
}

- (NSString *)cacheKeyForURL:(NSURL *)url {
    NSString *absolute = url.absoluteString ?: @"";
    NSString *cached = [self.keyCache objectForKey:absolute];
    if (cached) return cached;
    NSData *data = [absolute dataUsingEncoding:NSUTF8StringEncoding];
    unsigned char hash[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256(data.bytes, (CC_LONG)data.length, hash);
    NSMutableString *result = [NSMutableString stringWithCapacity:CC_SHA256_DIGEST_LENGTH * 2];
    for (NSUInteger i = 0; i < CC_SHA256_DIGEST_LENGTH; i++) {
        [result appendFormat:@"%02x", hash[i]];
    }
    NSString *key = [result copy];
    [self.keyCache setObject:key forKey:absolute];
    return key;
}

- (NSTimeInterval)ttlForURL:(NSURL *)url {
    NSString *host = url.host.lowercaseString ?: @"";
    if ([host isEqualToString:@"redd.it"] || [host hasSuffix:@".redd.it"] ||
        [host isEqualToString:@"reddit.com"] || [host hasSuffix:@".reddit.com"]) {
        return kRedditTTL;
    }
    if ([host isEqualToString:@"youtu.be"] || [host hasSuffix:@".youtube.com"] ||
        [host isEqualToString:@"youtube.com"]) {
        return kYouTubeTTL;
    }
    return kDefaultTTL;
}

- (BOOL)isFresh:(ApolloLinkPreviewModelSimple *)preview forURL:(NSURL *)url {
    NSTimeInterval age = [[NSDate date] timeIntervalSinceDate:preview.fetchedAt];
    return age >= 0 && age < [self ttlForURL:preview.url];
}

- (ApolloLinkPreviewModelSimple *)cachedPreviewForURL:(NSURL *)url {
    if (![url isKindOfClass:[NSURL class]]) return nil;
    NSString *key = [self cacheKeyForURL:url];

    ApolloLinkPreviewModelSimple *preview = [self.memoryCache objectForKey:key];
    if (preview && [self isFresh:preview forURL:url]) return preview;

    if ([self.missCache objectForKey:key]) return nil;
    [self.missCache setObject:@YES forKey:key];
    return nil;
}

- (void)storePreview:(ApolloLinkPreviewModelSimple *)preview forURL:(NSURL *)url {
    if (!preview || !url) return;
    [self.missCache removeObjectForKey:url.absoluteString];
    [self.memoryCache setObject:preview forKey:url.absoluteString];
    NSLog(@"ApolloPatcher:[LinkPreviews] cached preview for %@", url.absoluteString);
}

- (void)removePreviewForURL:(NSURL *)url {
    if (!url) return;
    [self.memoryCache removeObjectForKey:url.absoluteString];
    [self.missCache removeObjectForKey:url.absoluteString];
}

- (void)flushCache {
    [self.memoryCache removeAllObjects];
    [self.missCache removeAllObjects];
    NSLog(@"ApolloPatcher:[LinkPreviews] cache flushed");
}

@end