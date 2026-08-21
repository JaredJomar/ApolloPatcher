// ApolloLinkPreviewFetcherSimple.h
//
// Simplified fetcher for link preview metadata (Open Graph, Twitter Card, Reddit API).

#import <Foundation/Foundation.h>
#import "ApolloLinkPreviewModelSimple.h"

typedef void (^ApolloLinkPreviewFetchCompletion)(ApolloLinkPreviewModelSimple * _Nullable preview, NSError * _Nullable error);

@interface ApolloLinkPreviewFetcherSimple : NSObject

+ (instancetype _Nonnull)sharedFetcher;

- (void)fetchPreviewForURL:(NSURL * _Nonnull)url completion:(ApolloLinkPreviewFetchCompletion _Nullable)completion;

@end