// ApolloVideoUnmute.xm
//
// Auto-unmute videos in Comments header and Feed.
// Modes per context: Never (0) / Remember (1) / Always (2).
//
// Architecture:
// - Comments header: hook RichMediaHeaderCellNode + CommentsHeaderCellNode (crosspost)
//   cellNodeVisibilityEvent: auto-unmute on visible, re-unmute after fullscreen.
// - Feed: hook LargePostCellNode cellNodeVisibilityEvent (after %orig which decides autoplay)
//   One audible video at a time; hand-off mutes previous; retry chain for fast scroll.
// - Shared player handling: shareable v.redd.it player on videoNode.playerLayer.player
//   (videoNode.player is nil). Non-shareable: player on videoNode.player.
// - AVAudioSession hook: block reversion to Ambient while our player is audible.
// - AVPlayer.setMuted: hook: block mute on our auto-unmuted player (allow user manual mute).
// - PiP coordination: stubbed out (ApolloPictureInPicture.xm not ported).
// - Settings: UNMUTE_COMMENTS (0/1/2), UNMUTE_FEED (0/1/2), FEED_UNMUTED_MEMORY (bool).

#import "header.h"

#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>
#import <objc/runtime.h>
#import <objc/message.h>

// =============================================================================
// MARK: - PiP Stubs (ApolloPictureInPicture.xm not ported)
// =============================================================================

#ifndef ApolloPiP_HandleCommentsVisibilityEvent
#define ApolloPiP_HandleCommentsVisibilityEvent(...) NO
#define ApolloPiP_IsOwnedPlayer(...) NO
#define ApolloPiP_ShouldBlockAudioSessionDowngrade() NO
#define ApolloPiP_ShouldBlockMuteOfPlayer(...) NO
#define ApolloPiP_YieldAudioToPlayer(...)
#define ApolloPiP_NoteInlineVideoAudible(...)
#define ApolloPiP_NoteInlinePlayerMuted(...)
#define ApolloPiP_WillHandleFullscreenDismiss() NO
#endif

// =============================================================================
// MARK: - Settings Keys (inline, no UserDefaultConstants.h)
// =============================================================================

static NSString *const kUnmuteCommentsKey = @"UNMUTE_COMMENTS";
static NSString *const kUnmuteFeedKey = @"UNMUTE_FEED";
static NSString *const kFeedUnmutedMemoryKey = @"FEED_UNMUTED_MEMORY";

static NSInteger sUnmuteCommentsVideos = 0;
static NSInteger sUnmuteFeedVideos = 0;

// =============================================================================
// MARK: - State Variables
// =============================================================================

static const void *kAutoUnmuteAppliedKey = &kAutoUnmuteAppliedKey;
static __weak AVPlayer *sAutoUnmutedPlayer = nil;
static BOOL sIsAutoUnmuting = NO;
static BOOL sIsNavigatingBack = NO;
static __weak id sCommentsRichMediaNode = nil;
static __weak id sCommentsVideoNode = nil;
static __weak id sCommentsVCOwner = nil;
static __weak id sFeedAudibleRichMediaNode = nil;
static __weak id sFeedAudibleVideoNode = nil;
static NSUInteger sFeedUnmuteRetryGeneration = 0;

// =============================================================================
// MARK: - Helpers
// =============================================================================

static AVPlayer *GetPlayerFromVideoNode(id videoNode);
static void SyncMuteButtonIcon(id richMediaNode, BOOL isMuted);

static id GetIvarObject(id obj, const char *ivarName) {
    if (!obj) return nil;
    Ivar ivar = class_getInstanceVariable([obj class], ivarName);
    if (!ivar) return nil;
    return object_getIvar(obj, ivar);
}

static id GetIvarObjectQuiet(id obj, const char *ivarName) {
    if (!obj) return nil;
    Ivar ivar = class_getInstanceVariable([obj class], ivarName);
    return ivar ? object_getIvar(obj, ivar) : nil;
}

static BOOL GetIvarBool(id obj, const char *ivarName) {
    if (!obj) return NO;
    Ivar ivar = class_getInstanceVariable([obj class], ivarName);
    if (!ivar) return NO;
    ptrdiff_t offset = ivar_getOffset(ivar);
    return *(BOOL *)((uint8_t *)(__bridge void *)obj + offset);
}

static id GetVideoNodeFromRichMediaNode(id richMediaNode) {
    return richMediaNode ? GetIvarObjectQuiet(richMediaNode, "videoNode") : nil;
}

static id GetCrosspostRichMediaNodeFromOwner(id owner) {
    id crosspostNode = GetIvarObjectQuiet(owner, "crosspostNode");
    return crosspostNode ? GetIvarObjectQuiet(crosspostNode, "richMediaNode") : nil;
}

static BOOL ObjectsMatch(id lhs, id rhs) {
    return lhs && rhs && (lhs == rhs || [lhs isEqual:rhs]);
}

static UITableView *GetTableViewFromViewController(UIViewController *viewController) {
    UIView *rootView = [viewController view];
    if (!rootView) return nil;
    if ([rootView isKindOfClass:[UITableView class]]) return (UITableView *)rootView;
    for (UIView *subview in [rootView subviews]) {
        if ([subview isKindOfClass:[UITableView class]]) return (UITableView *)subview;
    }
    return nil;
}

static void EnumerateVisibleRichMediaNodes(UITableView *tableView, void (^block)(id richMediaNode)) {
    for (UITableViewCell *cell in [tableView visibleCells]) {
        SEL nodeSel = NSSelectorFromString(@"node");
        if (![cell respondsToSelector:nodeSel]) continue;
        id cellNode = ((id (*)(id, SEL))objc_msgSend)(cell, nodeSel);
        if (!cellNode) continue;
        id richMediaNode = GetIvarObjectQuiet(cellNode, "richMediaNode");
        if (richMediaNode) block(richMediaNode);
        id crosspostRichMediaNode = GetCrosspostRichMediaNodeFromOwner(cellNode);
        if (crosspostRichMediaNode) block(crosspostRichMediaNode);
    }
}

static Class PostsSearchResultsViewControllerClass(void) {
    static Class cls = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ cls = objc_getClass("_TtC6Apollo32PostsSearchResultsViewController"); });
    return cls;
}

static BOOL NodeIsInSearchResultsController(id node) {
    Class searchVCClass = PostsSearchResultsViewControllerClass();
    if (!searchVCClass || ![node respondsToSelector:@selector(view)]) return NO;
    UIResponder *responder = ((UIView *(*)(id, SEL))objc_msgSend)(node, @selector(view));
    while (responder) {
        if ([responder isKindOfClass:PostsSearchResultsViewControllerClass()]) return YES;
        responder = [responder nextResponder];
    }
    return NO;
}

static AVPlayer *GetPlayerFromVideoNode(id videoNode) {
    if (!videoNode) return nil;
    AVPlayerLayer *playerLayer = nil;
    SEL playerLayerSel = NSSelectorFromString(@"playerLayer");
    if ([videoNode respondsToSelector:playerLayerSel]) {
        CALayer *layer = ((CALayer *(*)(id, SEL))objc_msgSend)(videoNode, playerLayerSel);
        if ([layer isKindOfClass:[AVPlayerLayer class]]) playerLayer = (AVPlayerLayer *)layer;
    }
    AVPlayer *player = playerLayer ? [playerLayer player] : nil;
    if (player) return player;
    SEL playerSel = NSSelectorFromString(@"player");
    if ([videoNode respondsToSelector:playerSel]) {
        player = ((id (*)(id, SEL))objc_msgSend)(videoNode, playerSel);
        if (player) return player;
    }
    return nil;
}

static void SyncMuteButtonIcon(id richMediaNode, BOOL isMuted) {
    id muteButtonNode = GetIvarObject(richMediaNode, "muteUnmuteButtonNode");
    if (!muteButtonNode) return;
    BOOL currentIsMuted = GetIvarBool(muteButtonNode, "isMuted");
    if (currentIsMuted == isMuted) return;
    NSLog(@"ApolloPatcher:[VideoUnmute] SyncMuteButtonIcon: %@ -> %@",
          currentIsMuted ? @"muted" : @"unmuted", isMuted ? @"muted" : @"unmuted");
    Ivar isMutedIvar = class_getInstanceVariable([muteButtonNode class], "isMuted");
    if (isMutedIvar) {
        ptrdiff_t offset = ivar_getOffset(isMutedIvar);
        *(BOOL *)((uint8_t *)(__bridge void *)muteButtonNode + offset) = isMuted;
    }
    id iconNode = GetIvarObject(muteButtonNode, "icon");
    if (iconNode && [iconNode respondsToSelector:@selector(setImage:)]) {
        NSString *imageName = isMuted ? @"small-mute" : @"small-unmute";
        UIImage *image = [UIImage imageNamed:imageName];
        if (image) ((void (*)(id, SEL, id))objc_msgSend)(iconNode, @selector(setImage:), image);
    }
}

static void SyncRichMediaNodeMuteButton(id richMediaNode) {
    id videoNode = GetVideoNodeFromRichMediaNode(richMediaNode);
    if (!videoNode) return;
    AVPlayer *player = GetPlayerFromVideoNode(videoNode);
    if (!player) return;
    SyncMuteButtonIcon(richMediaNode, [player isMuted]);
}

static void SyncVisibleCellMuteButtons(id cellNode) {
    if (!cellNode) return;
    SyncRichMediaNodeMuteButton(GetIvarObjectQuiet(cellNode, "richMediaNode"));
    SyncRichMediaNodeMuteButton(GetCrosspostRichMediaNodeFromOwner(cellNode));
}

#pragma mark - Core Unmute Logic

static void UnmuteRichMediaNode(id richMediaNode, id videoNode) {
    AVPlayer *player = GetPlayerFromVideoNode(videoNode);
    if (!player) {
        NSLog(@"ApolloPatcher:[VideoUnmute] UnmuteRichMediaNode: no player found");
        return;
    }
    BOOL alreadyUnmuted = ![player isMuted];
    ApolloPiP_YieldAudioToPlayer(player);
    NSLog(@"ApolloPatcher:[VideoUnmute] UnmuteRichMediaNode: %@",
          alreadyUnmuted ? @"player already unmuted, establishing protection" : @"starting unmute sequence...");
    AVAudioSession *session = [AVAudioSession sharedInstance];
    NSError *error = nil;
    [session setCategory:AVAudioSessionCategoryPlayback mode:AVAudioSessionModeDefault options:0 error:&error];
    if (error) NSLog(@"ApolloPatcher:[VideoUnmute] setCategory:Playback error: %@", error);
    error = nil;
    [session setActive:YES withOptions:0 error:&error];
    if (error) NSLog(@"ApolloPatcher:[VideoUnmute] setActive:YES error: %@", error);
    if (!alreadyUnmuted) {
        sIsAutoUnmuting = YES;
        [player setMuted:NO];
        SEL setMutedSel = NSSelectorFromString(@"setMuted:");
        if ([videoNode respondsToSelector:setMutedSel]) {
            ((void (*)(id, SEL, BOOL))objc_msgSend)(videoNode, setMutedSel, NO);
        }
        sIsAutoUnmuting = NO;
    }
    sAutoUnmutedPlayer = player;
    SyncMuteButtonIcon(richMediaNode, NO);
    ApolloPiP_NoteInlineVideoAudible(videoNode, player);
    NSLog(@"ApolloPatcher:[VideoUnmute] Auto-unmute complete for player %p", player);
}

static void ReUnmuteAfterFullscreenWhenReady(id richMediaNode, id videoNode, NSUInteger attemptsRemaining) {
    if (!richMediaNode || !videoNode) {
        NSLog(@"ApolloPatcher:[VideoUnmute] Re-unmute after fullscreen: nodes deallocated");
        return;
    }
    AVPlayer *player = GetPlayerFromVideoNode(videoNode);
    if (!player) {
        if (attemptsRemaining > 0) {
            NSLog(@"ApolloPatcher:[VideoUnmute] Re-unmute after fullscreen: player not ready, retrying (%lu left)",
                  (unsigned long)attemptsRemaining);
            __weak id weakRichMediaNode = richMediaNode;
            __weak id weakVideoNode = videoNode;
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.15 * NSEC_PER_SEC)),
                           dispatch_get_main_queue(), ^{
                ReUnmuteAfterFullscreenWhenReady(weakRichMediaNode, weakVideoNode, attemptsRemaining - 1);
            });
        } else {
            NSLog(@"ApolloPatcher:[VideoUnmute] Re-unmute after fullscreen: no player found");
        }
        return;
    }
    NSLog(@"ApolloPatcher:[VideoUnmute] Re-unmuting after fullscreen dismiss");
    UnmuteRichMediaNode(richMediaNode, videoNode);
}

// =============================================================================
// MARK: - Comments Header (sUnmuteCommentsVideos)
// =============================================================================

static void HandleCommentsRichMediaVisibilityEvent(id visibilityOwner, id richMediaNode, unsigned long long event, NSString *contextLabel) {
    if (!visibilityOwner || !richMediaNode) return;
    if (event == 2) { // Invisible
        if (sIsNavigatingBack) {
            NSLog(@"ApolloPatcher:[VideoUnmute] %@ cell invisible during back nav — keeping protection", contextLabel);
            return;
        }
        NSLog(@"ApolloPatcher:[VideoUnmute] %@ cell invisible — clearing protection and refs", contextLabel);
        sAutoUnmutedPlayer = nil;
        id videoNode = GetVideoNodeFromRichMediaNode(richMediaNode);
        if (videoNode) {
            SEL setMutedSel = NSSelectorFromString(@"setMuted:");
            if ([videoNode respondsToSelector:setMutedSel]) {
                ((void (*)(id, SEL, BOOL))objc_msgSend)(videoNode, setMutedSel, YES);
            }
            AVPlayer *player = GetPlayerFromVideoNode(videoNode);
            if (player) [player setMuted:YES];
        }
        sCommentsRichMediaNode = nil;
        sCommentsVideoNode = nil;
        return;
    }
    BOOL unmuteApplied = objc_getAssociatedObject(visibilityOwner, kAutoUnmuteAppliedKey) != nil;
    id videoNode = GetVideoNodeFromRichMediaNode(richMediaNode);
    if (!videoNode) return;
    if (sUnmuteCommentsVideos >= 1) {
        sCommentsRichMediaNode = richMediaNode;
        sCommentsVideoNode = videoNode;
    }
    AVPlayer *player = GetPlayerFromVideoNode(videoNode);
    if (!player) {
        NSLog(@"ApolloPatcher:[VideoUnmute] %@ player not ready (event=%llu), scheduling retry", contextLabel, event);
        __weak id weakOwner = visibilityOwner;
        __weak id weakRichMediaNode = richMediaNode;
        __weak id weakVideoNode = videoNode;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            id strongOwner = weakOwner; id rmNode = weakRichMediaNode; id vNode = weakVideoNode;
            if (!strongOwner || !rmNode || !vNode) return;
            AVPlayer *retryPlayer = GetPlayerFromVideoNode(vNode);
            if (!retryPlayer) {
                NSLog(@"ApolloPatcher:[VideoUnmute] %@ retry: player still not ready", contextLabel);
                return;
            }
            SyncMuteButtonIcon(rmNode, [retryPlayer isMuted]);
            if (sUnmuteCommentsVideos == 2 && !objc_getAssociatedObject(strongOwner, kAutoUnmuteAppliedKey)) {
                objc_setAssociatedObject(strongOwner, kAutoUnmuteAppliedKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
                NSLog(@"ApolloPatcher:[VideoUnmute] %@ retry: unmuting after delay (muted=%d)", contextLabel, [retryPlayer isMuted]);
                UnmuteRichMediaNode(rmNode, vNode);
            }
        });
        return;
    }
    SyncMuteButtonIcon(richMediaNode, [player isMuted]);
    if (sUnmuteCommentsVideos != 2) return;
    if (unmuteApplied) return;
    objc_setAssociatedObject(visibilityOwner, kAutoUnmuteAppliedKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    NSLog(@"ApolloPatcher:[VideoUnmute] %@ auto-unmuting (event=%llu, muted=%d)", contextLabel, event, [player isMuted]);
    UnmuteRichMediaNode(richMediaNode, videoNode);
}

// =============================================================================
// MARK: - Feed (sUnmuteFeedVideos)
// =============================================================================

static BOOL FeedVideosShouldBeAudible(void) {
    if (sUnmuteFeedVideos == 2) return YES;
    if (sUnmuteFeedVideos == 1) {
        return [[NSUserDefaults standardUserDefaults] boolForKey:kFeedUnmutedMemoryKey];
    }
    return NO;
}

static void NoteFeedMuteButtonChoice(BOOL nowAudible) {
    if (sUnmuteFeedVideos != 1) return;
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    if ([defaults boolForKey:kFeedUnmutedMemoryKey] == nowAudible) return;
    [defaults setBool:nowAudible forKey:kFeedUnmutedMemoryKey];
    NSLog(@"ApolloPatcher:[VideoUnmute] Feed Remember: user %@ a feed video", nowAudible ? @"unmuted" : @"muted");
}

static void MutePreviouslyAudibleFeedVideo(AVPlayer *incoming) {
    id previousNode = sFeedAudibleRichMediaNode;
    AVPlayer *previous = sAutoUnmutedPlayer;
    if (!previous || previous == incoming) return;
    if (ApolloPiP_IsOwnedPlayer(previous)) return;
    sAutoUnmutedPlayer = nil;
    [previous setMuted:YES];
    id previousVideoNode = sFeedAudibleVideoNode;
    if (previousVideoNode) {
        SEL setMutedSel = NSSelectorFromString(@"setMuted:");
        if ([previousVideoNode respondsToSelector:setMutedSel]) {
            ((void (*)(id, SEL, BOOL))objc_msgSend)(previousVideoNode, setMutedSel, YES);
        }
    }
    if (previousNode) SyncMuteButtonIcon(previousNode, YES);
    NSLog(@"ApolloPatcher:[VideoUnmute] Feed audio handed to next video");
}

static BOOL ApplyFeedUnmuteIfNeeded(id richMediaNode, NSString *reason) {
    if (sUnmuteFeedVideos == 0 || !richMediaNode) return NO;
    if (GetIvarBool(richMediaNode, "isShownInCommentsHeader")) return NO;
    id videoNode = GetVideoNodeFromRichMediaNode(richMediaNode);
    if (!videoNode) return NO;
    AVPlayer *player = GetPlayerFromVideoNode(videoNode);
    if (!player) return NO;
    if (ApolloPiP_IsOwnedPlayer(player)) return NO;
    if (player == sAutoUnmutedPlayer && ![player isMuted]) return YES;
    if ([player rate] <= 0.0f) return NO;
    if (!FeedVideosShouldBeAudible()) return NO;
    MutePreviouslyAudibleFeedVideo(player);
    sFeedAudibleRichMediaNode = richMediaNode;
    sFeedAudibleVideoNode = videoNode;
    NSLog(@"ApolloPatcher:[VideoUnmute] Feed auto-unmute (%@, mode=%ld)", reason, (long)sUnmuteFeedVideos);
    UnmuteRichMediaNode(richMediaNode, videoNode);
    return YES;
}

static void ScheduleFeedUnmuteRetry(id richMediaNode, NSUInteger attemptsRemaining, NSUInteger generation) {
    if (attemptsRemaining == 0 || !richMediaNode) return;
    __weak id weakNode = richMediaNode;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.35 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (generation != sFeedUnmuteRetryGeneration) return;
        id node = weakNode;
        if (!node) return;
        if (ApplyFeedUnmuteIfNeeded(node, @"retry")) return;
        ScheduleFeedUnmuteRetry(node, attemptsRemaining - 1, generation);
    });
}

static void ReleaseFeedAudioIfOwnedBy(id richMediaNode) {
    if (!richMediaNode || !ObjectsMatch(richMediaNode, sFeedAudibleRichMediaNode)) return;
    NSLog(@"ApolloPatcher:[VideoUnmute] Feed audible cell left screen");
    id videoNode = GetVideoNodeFromRichMediaNode(richMediaNode);
    AVPlayer *player = videoNode ? GetPlayerFromVideoNode(videoNode) : nil;
    if (player && player == sAutoUnmutedPlayer) sAutoUnmutedPlayer = nil;
    if (player) [player setMuted:YES];
    if (videoNode) {
        SEL setMutedSel = NSSelectorFromString(@"setMuted:");
        if ([videoNode respondsToSelector:setMutedSel]) {
            ((void (*)(id, SEL, BOOL))objc_msgSend)(videoNode, setMutedSel, YES);
        }
    }
    SyncMuteButtonIcon(richMediaNode, YES);
    sFeedAudibleRichMediaNode = nil;
    sFeedAudibleVideoNode = nil;
}

static void ScheduleFeedUnmuteAfterFullscreen(void) {
    if (sUnmuteFeedVideos == 0 || !sFeedAudibleRichMediaNode) return;
    __weak id weakNode = sFeedAudibleRichMediaNode;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.3 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        id node = weakNode;
        if (!node) return;
        ApplyFeedUnmuteIfNeeded(node, @"after fullscreen dismiss");
    });
}

static void HandleFeedCellVisibilityEvent(id cellNode, unsigned long long event) {
    id richMediaNode = GetIvarObjectQuiet(cellNode, "richMediaNode");
    id crosspostNode = GetCrosspostRichMediaNodeFromOwner(cellNode);
    if (event == 2) { // Invisible
        ReleaseFeedAudioIfOwnedBy(richMediaNode);
        ReleaseFeedAudioIfOwnedBy(crosspostNode);
        return;
    }
    BOOL applied = ApplyFeedUnmuteIfNeeded(richMediaNode, @"visible");
    if (!applied) applied = ApplyFeedUnmuteIfNeeded(crosspostNode, @"visible crosspost");
if (!applied && event == 0 && (richMediaNode || crosspostNode)) {
        NSUInteger generation = ++sFeedUnmuteRetryGeneration;
        ScheduleFeedUnmuteRetry(richMediaNode ?: crosspostNode, 4, generation);
    }
}

// =============================================================================
// MARK: - Hooks
// =============================================================================

%hook RichMediaHeaderCellNode
- (void)cellNodeVisibilityEvent:(unsigned long long)event inScrollView:(id)scrollView withCellFrame:(CGRect)frame {
    id richMediaNode = GetIvarObject(self, "richMediaNode");
    if (ApolloPiP_HandleCommentsVisibilityEvent(self, richMediaNode, event)) return;
    %orig;
    if (event == 1) return;
    HandleCommentsRichMediaVisibilityEvent(self, richMediaNode, event, @"comments header video");
}
%end

%hook CommentsHeaderCellNode
- (void)cellNodeVisibilityEvent:(unsigned long long)event inScrollView:(id)scrollView withCellFrame:(CGRect)frame {
    id crosspostRichMediaNode = GetCrosspostRichMediaNodeFromOwner(self);
    if (ApolloPiP_HandleCommentsVisibilityEvent(self, crosspostRichMediaNode, event)) return;
    %orig;
    if (event == 1) return;
    if (!crosspostRichMediaNode) return;
    HandleCommentsRichMediaVisibilityEvent(self, crosspostRichMediaNode, event, @"comments crosspost video");
}
%end

%hook LargePostCellNode
- (void)cellNodeVisibilityEvent:(unsigned long long)event inScrollView:(id)scrollView withCellFrame:(CGRect)frame {
    %orig;
    if (sUnmuteFeedVideos == 0) return;
    HandleFeedCellVisibilityEvent(self, event);
}
%end

%hook RichMediaNode
- (void)unpauseAllAVPlayersNotificationReceivedWithNotification:(id)notification {
    %orig;
    if (!GetIvarBool(self, "isShownInCommentsHeader") && self != sCommentsRichMediaNode) return;
    id videoNode = GetIvarObject(self, "videoNode");
    if (!videoNode) return;
    SEL shareableSel = NSSelectorFromString(@"allowPlayerLayerToBeShareable");
    if (![videoNode respondsToSelector:shareableSel]) return;
    BOOL isShareable = ((BOOL (*)(id, SEL))objc_msgSend)(videoNode, shareableSel);
    if (!isShareable) return;
    AVPlayer *player = GetPlayerFromVideoNode(videoNode);
    if (!player) return;
    NSLog(@"ApolloPatcher:[VideoUnmute] unpauseAllAVPlayers: resuming shareable comments header video");
    [player play];
}
%end

%hook AVAudioSession
- (BOOL)setCategory:(AVAudioSessionCategory)category mode:(AVAudioSessionMode)mode options:(AVAudioSessionCategoryOptions)options error:(NSError * _Nullable *)error {
    if (ApolloPiP_ShouldBlockAudioSessionDowngrade()) return YES;
    if (sAutoUnmutedPlayer && category == AVAudioSessionCategoryAmbient) {
        NSLog(@"ApolloPatcher:[VideoUnmute] Blocking AVAudioSession downgrade to Ambient");
        if (error) *error = nil;
        return YES;
    }
    return %orig;
}
%end

%hook AVPlayer
- (void)setMuted:(BOOL)muted {
    if (sIsAutoUnmuting) return %orig;
    if (ApolloPiP_ShouldBlockMuteOfPlayer(self)) return %orig;
    if (sAutoUnmutedPlayer && self == sAutoUnmutedPlayer && muted) {
        NSLog(@"ApolloPatcher:[VideoUnmute] Blocking mute on auto-unmuted player");
        return;
    }
    %orig;
}
%end

%ctor {
    sUnmuteCommentsVideos = [[NSUserDefaults standardUserDefaults] integerForKey:kUnmuteCommentsKey];
    sUnmuteFeedVideos = [[NSUserDefaults standardUserDefaults] integerForKey:kUnmuteFeedKey];
    NSLog(@"ApolloPatcher:[VideoUnmute] module loaded (comments=%ld, feed=%ld)", (long)sUnmuteCommentsVideos, (long)sUnmuteFeedVideos);
}