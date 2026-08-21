// ApolloLinkPreviewModelSimple.m

#import "ApolloLinkPreviewModelSimple.h"

@implementation ApolloLinkPreviewModelSimple

- (instancetype)initWithURL:(NSURL *)url
                       title:(NSString *)title
                        desc:(NSString *)desc
                    imageURL:(NSURL *)imageURL
                  faviconURL:(NSURL *)faviconURL
                    siteName:(NSString *)siteName {
    self = [super init];
    if (self) {
        _url = [url copy];
        _title = [title copy];
        _desc = [desc copy];
        _imageURL = [imageURL copy];
        _faviconURL = [faviconURL copy];
        _siteName = [siteName copy];
        _fetchedAt = [NSDate date];
    }
    return self;
}

+ (instancetype)previewWithDictionary:(NSDictionary *)dict {
    if (!dict) return nil;
    NSURL *url = [NSURL URLWithString:dict[@"url"] ?: @""];
    if (!url) return nil;
    return [[self alloc] initWithURL:url
                                  title:dict[@"title"] ?: @""
                                   desc:dict[@"desc"] ?: @""
                               imageURL:[NSURL URLWithString:dict[@"imageURL"] ?: @""]
                             faviconURL:[NSURL URLWithString:dict[@"faviconURL"] ?: @""]
                               siteName:dict[@"siteName"] ?: @""];
}

- (NSDictionary *)dictionaryRepresentation {
    return @{
        @"url": self.url.absoluteString ?: @"",
        @"title": self.title ?: @"",
        @"desc": self.desc ?: @"",
        @"imageURL": self.imageURL.absoluteString ?: @"",
        @"faviconURL": self.faviconURL.absoluteString ?: @"",
        @"siteName": self.siteName ?: @"",
        @"fetchedAt": @([self.fetchedAt timeIntervalSince1970]),
    };
}

@end