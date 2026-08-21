// ApolloLinkPreviewCacheSimple.h
//
// Simplified in-memory cache for link previews with TTL per host.
// No disk persistence — pure NSCache with timestamp-based eviction.

#import <Foundation/Foundation.h>
#import "ApolloLinkPreviewModelSimple.h"

@interface ApolloLinkPreviewCacheSimple : NSObject

+ (instancetype)sharedCache;

- (ApolloLinkPreviewModelSimple *)cachedPreviewForURL:(NSURL *)url;
- (void)storePreview:(ApolloLinkPreviewModelSimple *)preview forURL:(NSURL *)url;
- (void)removePreviewForURL:(NSURL *)url;
- (void)flushCache;

@end