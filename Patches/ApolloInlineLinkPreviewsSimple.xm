// ApolloInlineLinkPreviewsSimple.xm
//
// Simplified inline link previews for ApolloPatcher.
// Hooks LinkButtonNode / ASNetworkImageNode to show preview cards.

#import "header.h"
#import "ApolloLinkPreviewCacheSimple.h"
#import "ApolloLinkPreviewFetcherSimple.h"
#import "ApolloLinkPreviewModelSimple.h"

#import <UIKit/UIKit.h>
#import <AsyncDisplayKit/AsyncDisplayKit.h>
#import <objc/runtime.h>
#import <objc/message.h>

// Forward declarations
@class ASLayoutSpec;
@class ASStackLayoutSpec;
@class ASInsetLayoutSpec;
@class ASRatioLayoutSpec;
@class ASBackgroundLayoutSpec;
@class ASDisplayNode;
@class ASNetworkImageNode;
@class ASTextNode;
@class ASButtonNode;

@interface ASDisplayNode : NSObject
- (void)addSubnode:(ASDisplayNode *)subnode;
- (ASDisplayNode *)supernode;
- (NSArray *)subnodes;
- (id)style;
- (UIView *)view;
- (BOOL)isNodeLoaded;
- (void)setNeedsLayout;
@property (nonatomic, readonly) NSUInteger interfaceState;
@property (nonatomic, copy) UIColor *backgroundColor;
@property (nonatomic) CGFloat cornerRadius;
@property (nonatomic) BOOL clipsToBounds;
@property (nonatomic) BOOL userInteractionEnabled;
@property (nonatomic) CGFloat alpha;
@property (nonatomic, getter=isHidden) BOOL hidden;
@end

@interface ASTextNode : ASDisplayNode
@property (nonatomic, copy) NSAttributedString *attributedText;
@property (nonatomic) NSUInteger maximumNumberOfLines;
@property (nonatomic) NSLineBreakMode truncationMode;
@end

@interface ASNetworkImageNode : ASDisplayNode
@property (nullable, copy) NSURL *URL;
@property (nullable, nonatomic, strong) UIImage *image;
@property (nullable, nonatomic, strong) UIImage *defaultImage;
@property (nonatomic) UIViewContentMode contentMode;
@property (nonatomic) CGRect cropRect;
@property (nonatomic) BOOL clipsToBounds;
@property (nonatomic) BOOL placeholderEnabled;
@property (nonatomic, copy) UIColor *placeholderColor;
@end

@interface ASLayoutSpec : NSObject
@property (nullable, nonatomic) NSArray *children;
- (id)style;
@end

@interface ASStackLayoutSpec : ASLayoutSpec
@property (nonatomic) NSInteger direction; // 0=vertical, 1=horizontal
@property (nonatomic) CGFloat spacing;
@property (nonatomic) NSInteger justifyContent;
@property (nonatomic) NSInteger alignItems;
+ (instancetype)stackLayoutSpecWithDirection:(NSInteger)direction
                                      spacing:(CGFloat)spacing
                               justifyContent:(NSInteger)justifyContent
                                   alignItems:(NSInteger)alignItems
                                     children:(NSArray *)children;
@end

@interface ASInsetLayoutSpec : ASLayoutSpec
+ (instancetype)insetLayoutSpecWithInsets:(UIEdgeInsets)insets child:(id)child;
@end

@interface ASRatioLayoutSpec : ASLayoutSpec
+ (instancetype)ratioLayoutSpecWithRatio:(CGFloat)ratio child:(id)child;
@end

@interface ASButtonNode : ASDisplayNode
- (void)addTarget:(id)target action:(SEL)action forControlEvents:(NSInteger)controlEvents;
@end

static char kLinkPreviewURLKey;
static char kLinkPreviewNodeKey;
static char kLinkPreviewFetchingKey;

static NSHashTable *sRegisteredNodes = nil;
static NSObject *sRegisteredNodesLock = nil;

static void ApolloLPRegisterNode(id node, NSURL *url) {
    if (!sRegisteredNodes) {
        @synchronized (sRegisteredNodesLock ?: (sRegisteredNodesLock = [NSObject new])) {
            if (!sRegisteredNodes) {
                sRegisteredNodes = [NSHashTable weakObjectsHashTable];
            }
        }
    }
    objc_setAssociatedObject(node, &kLinkPreviewURLKey, url, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [sRegisteredNodes addObject:node];
}

static NSURL *ApolloLPGetURLForNode(id node) {
    return objc_getAssociatedObject(node, &kLinkPreviewURLKey);
}

static BOOL ApolloLPIsFetching(id node) {
    return [objc_getAssociatedObject(node, &kLinkPreviewFetchingKey) boolValue];
}

static void ApolloLPSetFetching(id node, BOOL fetching) {
    objc_setAssociatedObject(node, &kLinkPreviewFetchingKey, @(fetching), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

static void ApolloLPSetPreviewNode(id node, id previewNode) {
    objc_setAssociatedObject(node, &kLinkPreviewNodeKey, previewNode, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

static id ApolloLPGetPreviewNode(id node) {
    return objc_getAssociatedObject(node, &kLinkPreviewNodeKey);
}

static void ApolloLPFetchAndAttachPreview(id node, NSURL *url) {
    if (!url || ApolloLPIsFetching(node)) return;
    ApolloLPSetFetching(node, YES);

    ApolloLinkPreviewModelSimple *cached = [[ApolloLinkPreviewCacheSimple sharedCache] cachedPreviewForURL:url];
    if (cached) {
        [self attachPreview:cached toNode:node];
        return;
    }

    [[ApolloLinkPreviewFetcherSimple sharedFetcher] fetchPreviewForURL:url completion:^(ApolloLinkPreviewModelSimple *preview, NSError *error) {
        if (preview) {
            [[ApolloLinkPreviewCacheSimple sharedCache] storePreview:preview forURL:url];
            [self attachPreview:preview toNode:node];
        } else {
            // Mark as no-preview to avoid refetch
            ApolloLPSetFetching(node, NO);
        }
    }];
}

static void ApolloLPAttachPreview(ApolloLinkPreviewModelSimple *preview, id node) {
    if (!preview || !preview.title.length && !preview.desc.length && !preview.imageURL) return;

    // Build preview card using Texture/AsyncDisplayKit nodes
    ASNetworkImageNode *imageNode = nil;
    if (preview.imageURL) {
        imageNode = [ASNetworkImageNode new];
        imageNode.URL = preview.imageURL;
        imageNode.contentMode = UIViewContentModeScaleAspectFill;
        imageNode.clipsToBounds = YES;
        imageNode.cornerRadius = 8.0;
        imageNode.style.preferredSize = CGSizeMake(120, 90);
    }

    ASTextNode *titleNode = nil;
    if (preview.title.length) {
        titleNode = [ASTextNode new];
        titleNode.attributedText = [[NSAttributedString alloc] initWithString:preview.title
            attributes:@{NSFontAttributeName: [UIFont boldSystemFontOfSize:15],
                         NSForegroundColorAttributeName: [UIColor labelColor]}];
        titleNode.maximumNumberOfLines = 2;
        titleNode.truncationMode = NSLineBreakByTruncatingTail;
    }

    ASTextNode *descNode = nil;
    if (preview.desc.length) {
        descNode = [ASTextNode new];
        descNode.attributedText = [[NSAttributedString alloc] initWithString:preview.desc
            attributes:@{NSFontAttributeName: [UIFont systemFontOfSize:13],
                         NSForegroundColorAttributeName: [UIColor secondaryLabelColor]}];
        descNode.maximumNumberOfLines = 3;
        descNode.truncationMode = NSLineBreakByTruncatingTail;
    }

    ASTextNode *siteNode = nil;
    if (preview.siteName.length) {
        siteNode = [ASTextNode new];
        siteNode.attributedText = [[NSAttributedString alloc] initWithString:preview.siteName
            attributes:@{NSFontAttributeName: [UIFont systemFontOfSize:11 weight:UIFontWeightMedium],
                         NSForegroundColorAttributeName: [UIColor tertiaryLabelColor]}];
    }

    NSMutableArray *textChildren = [NSMutableArray array];
    if (titleNode) [textChildren addObject:titleNode];
    if (descNode) [textChildren addObject:descNode];
    if (siteNode) [textChildren addObject:siteNode];

    ASStackLayoutSpec *textStack = [ASStackLayoutSpec stackLayoutSpecWithDirection:0
                                                                               spacing:4
                                                                        justifyContent:0
                                                                            alignItems:3
                                                                              children:textChildren];

    ASLayoutSpec *contentChild;
    if (imageNode) {
        ASStackLayoutSpec *contentStack = [ASStackLayoutSpec stackLayoutSpecWithDirection:1
                                                                                    spacing:12
                                                                                 justifyContent:0
                                                                                    alignItems:2
                                                                                      children:@[imageNode, textStack]];
        contentChild = contentStack;
    } else {
        contentChild = textStack;
    }

    ASInsetLayoutSpec *inset = [ASInsetLayoutSpec insetLayoutSpecWithInsets:UIEdgeInsetsMake(12, 12, 12, 12) child:contentChild];

    ASDisplayNode *cardNode = [ASDisplayNode new];
    cardNode.backgroundColor = [UIColor secondarySystemBackgroundColor];
    cardNode.cornerRadius = 12;
    cardNode.clipsToBounds = YES;
    [cardNode addSubnode:inset];

    ASRatioLayoutSpec *ratio = [ASRatioLayoutSpec ratioLayoutSpecWithRatio:1.0 child:cardNode];

    // Attach to the node
    id existingPreview = ApolloLPGetPreviewNode(node);
    if (existingPreview && [existingPreview isKindOfClass:[ASDisplayNode class]]) {
        [existingPreview removeFromSupernode];
    }
    ApolloLPSetPreviewNode(node, cardNode);

    // Insert preview node below the link button
    [node addSubnode:cardNode];
    [node setNeedsLayout];
}

%hook ASDisplayNode

- (ASLayoutSpec *)layoutSpecThatFits:(ASSizeRange)constrainedSize {
    ASLayoutSpec *orig = %orig;
    id previewNode = ApolloLPGetPreviewNode(self);
    if (!previewNode || ![previewNode isKindOfClass:[ASDisplayNode class]]) return orig;

    // Wrap original + preview in vertical stack
    ASStackLayoutSpec *stack = [ASStackLayoutSpec stackLayoutSpecWithDirection:0
                                                                           spacing:8
                                                                    justifyContent:0
                                                                        alignItems:3
                                                                          children:@[orig, previewNode]];
    return stack;
}

%end

%hook ASButtonNode

- (ASLayoutSpec *)layoutSpecThatFits:(ASSizeRange)constrainedSize {
    ASLayoutSpec *orig = %orig;
    id url = ApolloLPGetURLForNode(self);
    if (url && !ApolloLPGetPreviewNode(self) && !ApolloLPIsFetching(self)) {
        ApolloLPFetchAndAttachPreview(self, url);
    }
    return orig;
}

%end

%hook ASNetworkImageNode

- (ASLayoutSpec *)layoutSpecThatFits:(ASSizeRange)constrainedSize {
    ASLayoutSpec *orig = %orig;
    id url = ApolloLPGetURLForNode(self);
    if (url && !ApolloLPGetPreviewNode(self) && !ApolloLPIsFetching(self)) {
        ApolloLPFetchAndAttachPreview(self, url);
    }
    return orig;
}

%end

%ctor {
    NSLog(@"ApolloPatcher:[LinkPreviews] module loaded (simplified)");
}