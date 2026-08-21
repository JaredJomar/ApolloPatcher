// ApolloVideoPlaybackSpeed.xm
//
// Adds two extra playback-speed options — 0.75× and 1.25× — to Apollo's
// built-in video player speed menu.
//
// How Apollo's speed menu works:
// - The fullscreen media viewer (MediaViewerController, ObjC name
//   _TtC6Apollo21MediaViewerController) shows a native iOS context UIMenu
//   when you long-press the video. One of its rows is a "Playback Speed"
//   SUBMENU with rows "0.25×", "0.5×", "Normal", "1.5×", "2×".
// - The selected speed is stored on the controller as `videoPlaybackSpeed`
//   (a Swift Float? ivar: 4-byte value at offset, 1-byte "has value" flag
//   at offset+4; flag == 0 means .some, flag != 0 means .none/nil).
// - When playback starts the controller applies `player.setRate(videoPlaybackSpeed ?? 1.0)`.
// - When the speed is changed live while playing it calls `player.setRate(newSpeed)`
//   (only if `player.rate != 0`, i.e. it does not un-pause a paused video).
//
// Interception: UIKit always reads -[UIMenu children] to render the rows,
// so we hook that getter: when a menu's children are the speed rows, we
// return a cached augmented list with our own "0.75×"/"1.25×" UIActions spliced in.

#import "header.h"

#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>
#import <objc/runtime.h>
#import <objc/message.h>

static NSString *const kMediaViewerClassName = @"_TtC6Apollo21MediaViewerController";

static const float kSpeedSlow = 0.75f;
static const float kSpeedFast = 1.25f;

static NSString *MultiplicationSign(void) {
    return [NSString stringWithFormat:@"%C", (unichar)0x00D7];
}

static NSString *SpeedTitle(float speed) {
    NSString *num;
    if (speed == 0.25f)      num = @"0.25";
    else if (speed == 0.5f)  num = @"0.5";
    else if (speed == 0.75f) num = @"0.75";
    else if (speed == 1.25f) num = @"1.25";
    else if (speed == 1.5f)  num = @"1.5";
    else if (speed == 2.0f)  num = @"2";
    else                     num = [NSString stringWithFormat:@"%g", speed];
    return [num stringByAppendingString:MultiplicationSign()];
}

#pragma mark - Current media viewer tracking

static __weak UIViewController *sCurrentMediaViewer = nil;

static UIViewController *SearchMediaViewer(UIViewController *vc, Class cls) {
    if (!vc) return nil;
    if ([vc isMemberOfClass:cls]) return vc;
    for (UIViewController *child in vc.childViewControllers) {
        UIViewController *found = SearchMediaViewer(child, cls);
        if (found) return found;
    }
    return SearchMediaViewer(vc.presentedViewController, cls);
}

static UIViewController *CurrentMediaViewer(void) {
    UIViewController *tracked = sCurrentMediaViewer;
    if (tracked) return tracked;

    Class cls = objc_getClass([kMediaViewerClassName UTF8String]);
    if (!cls) return nil;
    if (@available(iOS 13.0, *)) {
        for (UIScene *scene in [UIApplication sharedApplication].connectedScenes) {
            if (![scene isKindOfClass:[UIWindowScene class]]) continue;
            for (UIWindow *window in ((UIWindowScene *)scene).windows) {
                UIViewController *found = SearchMediaViewer(window.rootViewController, cls);
                if (found) return found;
            }
        }
    }
    return nil;
}

#pragma mark - videoPlaybackSpeed ivar + player access

static BOOL ReadCurrentSpeed(UIViewController *mvc, float *outSpeed) {
    if (!mvc) return NO;
    Ivar ivar = class_getInstanceVariable([mvc class], "videoPlaybackSpeed");
    if (!ivar) return NO;
    uint8_t *base = (uint8_t *)(__bridge void *)mvc + ivar_getOffset(ivar);
    uint8_t hasValueFlag = base[4];
    if (hasValueFlag != 0) return NO;
    if (outSpeed) memcpy(outSpeed, base, sizeof(float));
    return YES;
}

static void WriteCurrentSpeed(UIViewController *mvc, float speed) {
    Ivar ivar = class_getInstanceVariable([mvc class], "videoPlaybackSpeed");
    if (!ivar) return;
    uint8_t *base = (uint8_t *)(__bridge void *)mvc + ivar_getOffset(ivar);
    memcpy(base, &speed, sizeof(float));
    base[4] = 0;
}

static AVPlayer *PlayerFromLayer(CALayer *layer) {
    if (!layer) return nil;
    if ([layer isKindOfClass:[AVPlayerLayer class]]) {
        AVPlayer *p = [(AVPlayerLayer *)layer player];
        if (p) return p;
    }
    for (CALayer *sub in layer.sublayers) {
        AVPlayer *p = PlayerFromLayer(sub);
        if (p) return p;
    }
    return nil;
}

static AVPlayer *PlayerFromView(UIView *view) {
    if (!view) return nil;
    SEL playerLayerSel = NSSelectorFromString(@"playerLayer");
    if ([view respondsToSelector:playerLayerSel]) {
        id pl = ((id (*)(id, SEL))objc_msgSend)(view, playerLayerSel);
        if ([pl isKindOfClass:[AVPlayerLayer class]]) {
            AVPlayer *p = [(AVPlayerLayer *)pl player];
            if (p) return p;
        }
    }
    AVPlayer *p = PlayerFromLayer(view.layer);
    if (p) return p;
    for (UIView *sub in view.subviews) {
        p = PlayerFromView(sub);
        if (p) return p;
    }
    return nil;
}

static AVPlayer *MediaViewerPlayer(UIViewController *mvc) {
    if (!mvc) return nil;

    Ivar playerIvar = class_getInstanceVariable([mvc class], "player");
    if (playerIvar) {
        id player = object_getIvar(mvc, playerIvar);
        if ([player isKindOfClass:[AVPlayer class]]) return (AVPlayer *)player;
    }

    Ivar containerIvar = class_getInstanceVariable([mvc class], "playerLayerContainerView");
    if (containerIvar) {
        id container = object_getIvar(mvc, containerIvar);
        if ([container isKindOfClass:[UIView class]]) {
            AVPlayer *p = PlayerFromView((UIView *)container);
            if (p) return p;
        }
    }

    return PlayerFromView(mvc.isViewLoaded ? mvc.view : nil);
}

static void ApplyPlaybackSpeed(float speed) {
    UIViewController *mvc = CurrentMediaViewer();
    if (!mvc) {
        NSLog(@"ApolloPatcher:[PlaybackSpeed] no media viewer found to apply %.2fx", speed);
        return;
    }

    WriteCurrentSpeed(mvc, speed);

    AVPlayer *player = MediaViewerPlayer(mvc);
    if (player && player.rate != 0.0f) {
        [player setRate:speed];
    }
    NSLog(@"ApolloPatcher:[PlaybackSpeed] applied %.2fx (player=%@ rate=%.2f)",
          speed, player ? @"yes" : @"nil", player ? player.rate : 0.0f);
}

#pragma mark - Speed submenu detection + augmentation

static NSString *ElementTitle(UIMenuElement *e) {
    return [e respondsToSelector:@selector(title)] ? [(id)e title] : nil;
}

static UIImage *ElementImage(UIMenuElement *e) {
    return [e respondsToSelector:@selector(image)] ? ((UIAction *)e).image : nil;
}

static BOOL TitleIsSpeed(NSString *title) {
    if (title.length < 2 || ![title hasSuffix:MultiplicationSign()]) return NO;
    NSString *num = [title substringToIndex:title.length - 1];
    if (num.length == 0) return NO;
    NSCharacterSet *nonNumeric = [[NSCharacterSet characterSetWithCharactersInString:@"0123456789."] invertedSet];
    return [num rangeOfCharacterFromSet:nonNumeric].location == NSNotFound;
}

static BOOL ShouldAugmentSpeedMenu(NSArray<UIMenuElement *> *children) {
    if (children.count < 3) return NO;

    NSUInteger speedCount = 0;
    for (UIMenuElement *element in children) {
        NSString *title = ElementTitle(element);
        if (!title) continue;
        if ([title isEqualToString:SpeedTitle(kSpeedSlow)] || [title isEqualToString:SpeedTitle(kSpeedFast)]) {
            return NO;
        }
        if (TitleIsSpeed(title)) speedCount++;
    }
    return speedCount >= 3;
}

#pragma mark - Row icons

static UIImage *LoadBundledSpeedIcon(NSString *name) {
    // We don't have ApolloBundledResourcePath; rely on fallback to neighbour icons
    return nil;
}

static UIImage *DeerIcon(void) {
    return LoadBundledSpeedIcon(@"playback-speed-deer");
}

static UIImage *FoxIcon(void) {
    return LoadBundledSpeedIcon(@"playback-speed-fox");
}

static UIImage *PreferredSpeedIcon(float speed, UIImage *fallback) {
    UIImage *img = nil;
    if (speed == kSpeedSlow) img = DeerIcon();
    else if (speed == kSpeedFast) img = FoxIcon();
    return img ?: fallback;
}

#pragma mark - Augmentation

static UIAction *MakeSpeedAction(float speed, UIImage *image, float currentSpeed, BOOL haveCurrent) {
    UIAction *action = [UIAction actionWithTitle:SpeedTitle(speed)
                                           image:image
                                      identifier:nil
                                         handler:^(__kindof UIAction *act) {
        ApplyPlaybackSpeed(speed);
    }];
    if (haveCurrent && fabsf(currentSpeed - speed) < 0.001f) {
        action.state = UIMenuElementStateOn;
    }
    return action;
}

static NSArray<UIMenuElement *> *AugmentedSpeedChildren(NSArray<UIMenuElement *> *children) {
    UIImage *slowImage = nil;
    UIImage *fastImage = nil;
    for (UIMenuElement *element in children) {
        NSString *title = ElementTitle(element);
        if ([title isEqualToString:SpeedTitle(0.5f)]) slowImage = ElementImage(element);
        else if ([title isEqualToString:SpeedTitle(1.5f)]) fastImage = ElementImage(element);
    }

    float current = 1.0f;
    BOOL haveCurrent = ReadCurrentSpeed(CurrentMediaViewer(), &current);

    UIAction *slowAction = MakeSpeedAction(kSpeedSlow, PreferredSpeedIcon(kSpeedSlow, slowImage), current, haveCurrent);
    UIAction *fastAction = MakeSpeedAction(kSpeedFast, PreferredSpeedIcon(kSpeedFast, fastImage), current, haveCurrent);

    NSMutableArray<UIMenuElement *> *result = [NSMutableArray arrayWithCapacity:children.count + 2];
    BOOL insertedSlow = NO, insertedFast = NO;
    for (UIMenuElement *element in children) {
        NSString *title = ElementTitle(element);
        if (!insertedFast && [title isEqualToString:SpeedTitle(1.5f)]) {
            [result addObject:fastAction];
            insertedFast = YES;
        }
        [result addObject:element];
        if (!insertedSlow && [title isEqualToString:SpeedTitle(0.5f)]) {
            [result addObject:slowAction];
            insertedSlow = YES;
        }
    }
    if (!insertedSlow) [result addObject:slowAction];
    if (!insertedFast) [result addObject:fastAction];
    return result;
}

#pragma mark - Hooks

%hook _TtC6Apollo21MediaViewerController

- (void)viewDidAppear:(BOOL)animated {
    %orig;
    sCurrentMediaViewer = (UIViewController *)self;
}

- (void)viewWillDisappear:(BOOL)animated {
    %orig;
    if (sCurrentMediaViewer == (UIViewController *)self) sCurrentMediaViewer = nil;
}

%end

%hook UIMenu

- (NSArray<UIMenuElement *> *)children {
    NSArray<UIMenuElement *> *orig = %orig;
    static char kAugmentedChildrenKey;
    NSArray<UIMenuElement *> *cached = objc_getAssociatedObject(self, &kAugmentedChildrenKey);
    if (cached) return cached;
    if (ShouldAugmentSpeedMenu(orig)) {
        NSArray<UIMenuElement *> *augmented = AugmentedSpeedChildren(orig);
        objc_setAssociatedObject(self, &kAugmentedChildrenKey, augmented, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        return augmented;
    }
    return orig;
}

%end

%ctor {
    NSLog(@"ApolloPatcher:[PlaybackSpeed] module loaded (adds 0.75x and 1.25x)");
}