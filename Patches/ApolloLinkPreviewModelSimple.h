// ApolloLinkPreviewModelSimple.h
//
// Simple data model for link preview metadata.

#import <Foundation/Foundation.h>

@interface ApolloLinkPreviewModelSimple : NSObject

@property (nonatomic, copy, readonly) NSString *title;
@property (nonatomic, copy, readonly) NSString *desc;
@property (nonatomic, copy, readonly) NSURL *imageURL;
@property (nonatomic, copy, readonly) NSURL *faviconURL;
@property (nonatomic, copy, readonly) NSString *siteName;
@property (nonatomic, copy, readonly) NSURL *url;
@property (nonatomic, readonly) NSDate *fetchedAt;

- (instancetype)initWithURL:(NSURL *)url
                       title:(NSString *)title
                        desc:(NSString *)desc
                    imageURL:(NSURL *)imageURL
                  faviconURL:(NSURL *)faviconURL
                    siteName:(NSString *)siteName;

+ (instancetype)previewWithDictionary:(NSDictionary *)dict;
- (NSDictionary *)dictionaryRepresentation;

@end