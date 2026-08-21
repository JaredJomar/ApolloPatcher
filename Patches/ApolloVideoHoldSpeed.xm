// ApolloVideoHoldSpeed.xm
//
// "Hold for Video Speed" — press-and-hold the RIGHT third of the fullscreen video
// to play it at a chosen speed while held; release to restore the previous rate.
//
// Settings keys (ApolloPatcher):
//   HOLD_SPEED_ENABLED  (BOOL, default YES)  master toggle
//   HOLD_SPEED          (float, default 2.0) speed applied while held
// Both are read once per launch; changes apply after an app restart.
//
// Coexists with Apollo's long-press context menu:
//
//     +--------------------------+------------+
//     |     left + center 2/3    |   right 1/3 |
//     |   normal long-press menu |  speed hold |
//     +--------------------------+------------+
//
// Uses a custom passive recognizer (never leaves .possible) so UIKit gesture
// arbitration can't kill it and it never blocks Apollo's own tap/pan handling.
// Context-menu interactions under the finger are removed on right-zone touch-down
// and restored on release, so the menu simply cannot appear for that press.
//
// Scrub interplay: Apollo's scrollViewScrubbed: snapshots player.rate into its
// initialRate ivar on .began and resumes with playImmediatelyAtRate: on end.
// An engaged hold is released BEFORE %orig on scrub-begin so the snapshot sees
// the clean pre-hold rate; while a scrub is in flight new holds never engage.

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <UIKit/UIGestureRecognizerSubclass.h>
#import <AVFoundation/AVFoundation.h>
#import <objc/runtime.h>
#import <objc/message.h>

#import "header.h"

// Upstream routes logs through os_log; call sites already embed the
// "VideoHoldSpeed:" tag — pass straight through to the NSLog macro.
#define ApolloLog(fmt, ...) NSLog(fmt, ##__VA_ARGS__)
#define ApolloLogDebug(fmt, ...) NSLog(fmt, ##__VA_ARGS__)

// =============================================================================
// Settings state (ApolloPatcher keys; read once per launch in %ctor)
// =============================================================================

static BOOL sVideoHoldSpeedEnabled = YES;
static float sVideoHoldSpeed = 2.0f;

// Our settings UI allows any value in 0.5-4.0; guard against junk regardless.
static float ApolloSanitizedHoldSpeed(float value) {
    if (!(value >= 0.25f && value <= 4.0f)) return 2.0f;
    return value;
}

// Rightmost fraction of the video that activates hold-to-speed.
static const CGFloat kRightZoneFraction = 1.0 / 3.0;

// How long the press must be held before the speed engages.
static const NSTimeInterval kHoldActivationDelay = 0.18;

// Movement (in points) that cancels a pending hold, so a drag becomes a normal
// scrub / swipe-to-dismiss instead of a speed-up.
static const CGFloat kHoldMoveTolerance = 12.0;

static const UIImpactFeedbackStyle kHoldHapticStyle = UIImpactFeedbackStyleMedium;

// Top-center overlay text for the engaged speed, e.g. "2x >>". Fast-forward
// chevrons only when boosting; bare multiplier for slow-motion speeds.
static NSAttributedString *HoldOverlayText(float speed) {
    NSString *num;
    if (fabsf(speed - 0.25f) < 0.001f)      num = @"0.25";
    else if (fabsf(speed - 0.5f)  < 0.001f) num = @"0.5";
    else if (fabsf(speed - 0.75f) < 0.001f) num = @"0.75";
    else if (fabsf(speed - 1.25f) < 0.001f) num = @"1.25";
    else if (fabsf(speed - 1.5f)  < 0.001f) num = @"1.5";
    else if (fabsf(speed - 2.0f)  < 0.001f) num = @"2";
    else                                    num = [NSString stringWithFormat:@"%g", speed];
    NSString *s = (speed > 1.0f)
        ? [NSString stringWithFormat:@"%@%C \u23E5\u23E5", num, (unichar)0x00D7]
        : [NSString stringWithFormat:@"%@%C", num, (unichar)0x00D7];
    return [[NSAttributedString alloc] initWithString:s attributes:@{
        NSFontAttributeName: [UIFont systemFontOfSize:17.0 weight:UIFontWeightSemibold],
        NSForegroundColorAttributeName: [UIColor whiteColor],
    }];
}

#pragma mark - Player access

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

// MediaViewerController stores its AVPlayer two ways: directly on the `player`
// ivar for non-shareable videos, or on the `playerLayerContainerView`'s
// AVPlayerLayer for shareable v.redd.it videos (`player` ivar nil).
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

static BOOL LayerHostsPlayer(CALayer *layer) {
    if ([layer isKindOfClass:[AVPlayerLayer class]]) return YES;
    for (CALayer *s in layer.sublayers) {
        if ([s isKindOfClass:[AVPlayerLayer class]]) return YES;
    }
    return NO;
}

static UIView *DeepestViewHostingPlayer(UIView *view) {
    if (!view) return nil;
    for (UIView *sub in view.subviews) {
        UIView *deep = DeepestViewHostingPlayer(sub);
        if (deep) return deep;
    }
    return LayerHostsPlayer(view.layer) ? view : nil;
}

static UIView *MediaVideoView(UIViewController *mvc) {
    if (!mvc) return nil;
    Ivar containerIvar = class_getInstanceVariable([mvc class], "playerLayerContainerView");
    if (containerIvar) {
        id c = object_getIvar(mvc, containerIvar);
        if ([c isKindOfClass:[UIView class]]) return (UIView *)c;
    }
    UIView *host = DeepestViewHostingPlayer(mvc.isViewLoaded ? mvc.view : nil);
    return host ?: (mvc.isViewLoaded ? mvc.view : nil);
}

// Collect every UIContextMenuInteraction in a view subtree, with the view that
// owns each (a UIInteraction's `view` is nilled once removed, so capture up front).
static void CollectContextMenuInteractions(UIView *view,
                                           NSMutableArray<UIView *> *outViews,
                                           NSMutableArray<UIContextMenuInteraction *> *outInteractions) {
    if (!view) return;
    for (id<UIInteraction> it in view.interactions) {
        if ([it isKindOfClass:[UIContextMenuInteraction class]]) {
            [outViews addObject:view];
            [outInteractions addObject:(UIContextMenuInteraction *)it];
        }
    }
    for (UIView *sub in view.subviews) {
        CollectContextMenuInteractions(sub, outViews, outInteractions);
    }
}

#pragma mark - Passive touch recognizer

@interface ApolloHoldTouchRecognizer : UIGestureRecognizer
@property (nonatomic, copy) void (^onTouchDown)(CGPoint windowPoint);
@property (nonatomic, copy) void (^onHoldElapsed)(CGPoint windowPoint);
@property (nonatomic, copy) void (^onTouchUp)(void);
@end

@implementation ApolloHoldTouchRecognizer {
    BOOL _armed;
    BOOL _holdFired;
    CGPoint _startWindow;
    NSInteger _generation;
}

- (void)scheduleHold {
    NSInteger gen = ++_generation;
    CGPoint start = _startWindow;
    __weak ApolloHoldTouchRecognizer *weakSelf = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(kHoldActivationDelay * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        ApolloHoldTouchRecognizer *s = weakSelf;
        if (!s || s->_generation != gen || s->_holdFired || !s->_armed) return;
        s->_holdFired = YES;
        if (s.onHoldElapsed) s.onHoldElapsed(start);
    });
}

- (void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    [super touchesBegan:touches withEvent:event];
    if (_armed) return;
    _armed = YES;
    _holdFired = NO;
    _startWindow = [touches.anyObject locationInView:nil];
    if (self.onTouchDown) self.onTouchDown(_startWindow);
    [self scheduleHold];
}

- (void)touchesMoved:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    [super touchesMoved:touches withEvent:event];
    if (!_armed || _holdFired) return;
    CGPoint p = [touches.anyObject locationInView:nil];
    if (hypot(p.x - _startWindow.x, p.y - _startWindow.y) > kHoldMoveTolerance) {
        _generation++;
    }
}

- (void)touchesEnded:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    [super touchesEnded:touches withEvent:event];
    [self finish];
}

- (void)touchesCancelled:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    [super touchesCancelled:touches withEvent:event];
    [self finish];
}

- (void)reset {
    [super reset];
    [self finish];
}

- (void)finish {
    if (!_armed) return;
    _generation++;
    _armed = NO;
    _holdFired = NO;
    if (self.onTouchUp) self.onTouchUp();
}

@end

#pragma mark - Handler

@interface ApolloHoldSpeedHandler : NSObject
@property (nonatomic, weak) UIViewController *mediaViewer;
@property (nonatomic, strong) ApolloHoldTouchRecognizer *recognizer;
@property (nonatomic, strong) UIView *overlayView;
@property (nonatomic, strong) UILabel *overlayLabel;
@property (nonatomic, assign) float engagedHoldSpeed;
@property (nonatomic, strong) NSArray<UIContextMenuInteraction *> *suppressedInteractions;
@property (nonatomic, strong) NSArray<UIView *> *suppressedInteractionViews;
@property (nonatomic, assign) BOOL inZone;
@property (nonatomic, assign) BOOL active;
@property (nonatomic, assign) BOOL scrubbing;
@property (nonatomic, assign) float preHoldRate;
@property (nonatomic, strong) UIImpactFeedbackGenerator *hapticGenerator;
// Held strongly so release restores THIS exact instance even if the media viewer
// is torn down mid-hold.
@property (nonatomic, strong) AVPlayer *engagedPlayer;
- (void)installOnView:(UIView *)view;
- (void)releaseHoldWithReason:(NSString *)reason;
@end

@implementation ApolloHoldSpeedHandler

- (void)installOnView:(UIView *)view {
    if (self.recognizer || !view) return;

    ApolloHoldTouchRecognizer *gr = [[ApolloHoldTouchRecognizer alloc] init];
    gr.cancelsTouchesInView = NO;
    gr.delaysTouchesBegan = NO;
    gr.delaysTouchesEnded = NO;

    __weak ApolloHoldSpeedHandler *weakSelf = self;
    gr.onTouchDown   = ^(CGPoint p) { [weakSelf touchDownAt:p]; };
    gr.onHoldElapsed = ^(CGPoint p) { [weakSelf holdElapsedAt:p]; };
    gr.onTouchUp     = ^{ [weakSelf touchUp]; };

    [view addGestureRecognizer:gr];
    self.recognizer = gr;
    ApolloLog(@"VideoHoldSpeed: installed on %@", NSStringFromClass([view class]));
}

#pragma mark Menu suppression

- (void)suppressMenu {
    UIView *root = self.mediaViewer.isViewLoaded ? self.mediaViewer.view : self.recognizer.view;
    NSMutableArray<UIView *> *views = [NSMutableArray array];
    NSMutableArray<UIContextMenuInteraction *> *interactions = [NSMutableArray array];
    CollectContextMenuInteractions(root, views, interactions);
    for (NSUInteger i = 0; i < interactions.count; i++) {
        [views[i] removeInteraction:interactions[i]];
    }
    self.suppressedInteractionViews = views;
    self.suppressedInteractions = interactions;
    ApolloLog(@"VideoHoldSpeed: removed %lu context-menu interaction(s)", (unsigned long)interactions.count);
}

- (void)restoreMenu {
    NSArray<UIContextMenuInteraction *> *interactions = self.suppressedInteractions;
    NSArray<UIView *> *views = self.suppressedInteractionViews;
    for (NSUInteger i = 0; i < interactions.count; i++) {
        [views[i] addInteraction:interactions[i]];
    }
    self.suppressedInteractions = nil;
    self.suppressedInteractionViews = nil;
}

#pragma mark Zone detection

// True when windowPoint is in the right third of the VIDEO as displayed, in any
// orientation. Projects onto the video's on-screen left-to-right axis.
- (BOOL)pointInActivationZone:(CGPoint)windowPoint {
    if (!MediaViewerPlayer(self.mediaViewer)) return NO;

    UIView *v = MediaVideoView(self.mediaViewer);
    UIWindow *win = v.window;
    if (!v || !win) return NO;
    CGSize b = v.bounds.size;
    if (b.width <= 0 || b.height <= 0) return NO;

    CGPoint leftMid  = [v convertPoint:CGPointMake(0,       b.height / 2) toView:win];
    CGPoint rightMid = [v convertPoint:CGPointMake(b.width, b.height / 2) toView:win];

    CGFloat dx = rightMid.x - leftMid.x;
    CGFloat dy = rightMid.y - leftMid.y;
    CGFloat len2 = dx * dx + dy * dy;
    if (len2 <= 0) return NO;

    CGFloat t = ((windowPoint.x - leftMid.x) * dx + (windowPoint.y - leftMid.y) * dy) / len2;
    return t >= (1.0 - kRightZoneFraction);
}

#pragma mark Touch lifecycle

- (void)touchDownAt:(CGPoint)windowPoint {
    if (!sVideoHoldSpeedEnabled) { self.inZone = NO; return; }
    self.inZone = [self pointInActivationZone:windowPoint];
    if (self.inZone) {
        [self suppressMenu];
        if (!self.hapticGenerator) {
            self.hapticGenerator = [[UIImpactFeedbackGenerator alloc] initWithStyle:kHoldHapticStyle];
        }
        [self.hapticGenerator prepare];
    }
}

- (void)holdElapsedAt:(CGPoint)windowPoint {
    if (!self.inZone || self.active) return;
    if (self.scrubbing) { ApolloLog(@"VideoHoldSpeed: engage skipped — scrub in progress"); return; }
    AVPlayer *player = MediaViewerPlayer(self.mediaViewer);
    if (!player) { ApolloLog(@"VideoHoldSpeed: holdElapsed — no player"); return; }

    float holdSpeed = ApolloSanitizedHoldSpeed(sVideoHoldSpeed);
    self.engagedHoldSpeed = holdSpeed;
    self.engagedPlayer = player;
    self.preHoldRate = player.rate;
    self.active = YES;
    [player setRate:holdSpeed];
    [self showOverlay];

    if (!self.hapticGenerator) {
        self.hapticGenerator = [[UIImpactFeedbackGenerator alloc] initWithStyle:kHoldHapticStyle];
    }
    [self.hapticGenerator impactOccurred];

    ApolloLog(@"VideoHoldSpeed: engaged %.2fx (prevRate=%.2f)", holdSpeed, self.preHoldRate);
}

- (void)touchUp {
    [self restoreMenu];
    self.inZone = NO;
    [self releaseHoldWithReason:@"touch-up"];
}

- (void)releaseHoldWithReason:(NSString *)reason {
    if (!self.active) return;
    self.active = NO;
    [self.engagedPlayer setRate:self.preHoldRate];
    self.engagedPlayer = nil;
    [self hideOverlay];
    ApolloLog(@"VideoHoldSpeed: released via %@ (restored rate=%.2f)", reason, self.preHoldRate);
}

- (void)dealloc {
    if (self.active && self.engagedPlayer) {
        [self.engagedPlayer setRate:self.preHoldRate];
    }
}

#pragma mark Overlay

- (void)showOverlay {
    UIView *host = self.mediaViewer.isViewLoaded ? self.mediaViewer.view : self.recognizer.view;
    if (!host) return;

    if (!self.overlayView) {
        UIVisualEffectView *blur = [[UIVisualEffectView alloc]
            initWithEffect:[UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemUltraThinMaterialDark]];
        blur.layer.cornerRadius = 16.0;
        blur.layer.cornerCurve = kCACornerCurveContinuous;
        blur.clipsToBounds = YES;
        blur.userInteractionEnabled = NO;

        UILabel *label = [[UILabel alloc] init];
        label.translatesAutoresizingMaskIntoConstraints = NO;
        [blur.contentView addSubview:label];
        [NSLayoutConstraint activateConstraints:@[
            [label.leadingAnchor constraintEqualToAnchor:blur.contentView.leadingAnchor constant:14.0],
            [label.trailingAnchor constraintEqualToAnchor:blur.contentView.trailingAnchor constant:-14.0],
            [label.topAnchor constraintEqualToAnchor:blur.contentView.topAnchor constant:8.0],
            [label.bottomAnchor constraintEqualToAnchor:blur.contentView.bottomAnchor constant:-8.0],
        ]];
        self.overlayLabel = label;
        self.overlayView = blur;
    }

    self.overlayLabel.attributedText = HoldOverlayText(self.engagedHoldSpeed);

    UIView *overlay = self.overlayView;
    if (overlay.superview != host) {
        [overlay removeFromSuperview];
        overlay.translatesAutoresizingMaskIntoConstraints = NO;
        [host addSubview:overlay];
        [NSLayoutConstraint activateConstraints:@[
            [overlay.centerXAnchor constraintEqualToAnchor:host.centerXAnchor],
            [overlay.topAnchor constraintEqualToAnchor:host.safeAreaLayoutGuide.topAnchor constant:24.0],
        ]];
    }
    [host bringSubviewToFront:overlay];
    overlay.alpha = 0.0;
    [UIView animateWithDuration:0.15 animations:^{ overlay.alpha = 1.0; }];
}

- (void)hideOverlay {
    UIView *overlay = self.overlayView;
    if (!overlay) return;
    [UIView animateWithDuration:0.2 animations:^{ overlay.alpha = 0.0; }];
}

@end

#pragma mark - Install hook

static char kHoldSpeedHandlerKey;

static void InstallHoldSpeed(UIViewController *mvc) {
    if (!mvc) return;
    ApolloHoldSpeedHandler *existing = objc_getAssociatedObject(mvc, &kHoldSpeedHandlerKey);
    if (existing.recognizer) return;

    UIView *targetView = mvc.isViewLoaded ? mvc.view : nil;
    if (!targetView) return;

    ApolloHoldSpeedHandler *handler = existing ?: [[ApolloHoldSpeedHandler alloc] init];
    handler.mediaViewer = mvc;
    objc_setAssociatedObject(mvc, &kHoldSpeedHandlerKey, handler, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [handler installOnView:targetView];
}

%hook _TtC6Apollo21MediaViewerController

- (void)viewDidAppear:(BOOL)animated {
    %orig;
    InstallHoldSpeed((UIViewController *)self);
}

- (void)viewDidLayoutSubviews {
    %orig;
    InstallHoldSpeed((UIViewController *)self);
}

- (void)scrollViewScrubbed:(UIGestureRecognizer *)gestureRecognizer {
    ApolloHoldSpeedHandler *handler = objc_getAssociatedObject(self, &kHoldSpeedHandlerKey);
    UIGestureRecognizerState state = gestureRecognizer.state;
    if (state == UIGestureRecognizerStateBegan) {
        handler.scrubbing = YES;
        [handler releaseHoldWithReason:@"scrub-begin"];
    }
    %orig;
    if (state == UIGestureRecognizerStateEnded ||
        state == UIGestureRecognizerStateCancelled ||
        state == UIGestureRecognizerStateFailed) {
        handler.scrubbing = NO;
        ApolloLog(@"VideoHoldSpeed: scrub ended (player rate=%.2f)",
                  MediaViewerPlayer((UIViewController *)self).rate);
    }
}

%end

// NOTE: an explicit %ctor MUST call %init itself — Logos does not auto-generate
// hook installation when a custom constructor exists (this exact omission is
// what previously killed every hook in the unmute module).
%ctor {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    if ([defaults objectForKey:@"HOLD_SPEED_ENABLED"] != nil) {
        sVideoHoldSpeedEnabled = [defaults boolForKey:@"HOLD_SPEED_ENABLED"];
    } else {
        sVideoHoldSpeedEnabled = YES;
    }
    sVideoHoldSpeed = ApolloSanitizedHoldSpeed([defaults floatForKey:@"HOLD_SPEED"]);

    %init();

    ApolloLog(@"VideoHoldSpeed: module loaded (enabled=%d, speed=%.2f)",
              sVideoHoldSpeedEnabled, sVideoHoldSpeed);
}
