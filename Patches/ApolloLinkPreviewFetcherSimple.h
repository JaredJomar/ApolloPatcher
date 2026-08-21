// ApolloLinkPreviewFetcherSimple.h
//
// Simplified fetcher for link preview metadata (Open Graph, Twitter Card, Reddit API).

#import <Foundation/Foundation.h>
#import "ApolloLinkPreviewModelSimple.h"

typedef void (^ApolloLinkPreviewFetchCompletion)(ApolloLinkPreviewModelSimple * _Nullable preview, NSError * _Nullable error);

@interface ApolloLinkPreviewFetcherSimple : NSObject

+ (instancetype)sharedFetcher;

- (void)fetchPreviewForURL:(NSURL *)url completion:(ApolloLinkPreviewFetchCompletion)completion;

@end