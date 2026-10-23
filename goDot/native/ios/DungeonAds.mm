#import <UIKit/UIKit.h>
#import <AnyThinkSDK/AnyThinkSDK.h>
#import <AnyThinkRewardedVideo/AnyThinkRewardedVideo.h>
#import <UserMessagingPlatform/UserMessagingPlatform.h>
#include "core/config/engine.h"
#include "core/object/class_db.h"

@interface DungeonAdsDelegate : NSObject <ATAdLoadingDelegate, ATRewardedVideoDelegate>
@property(nonatomic, strong) NSMutableArray *events;
@property(nonatomic, copy) NSString *placement;
@property(nonatomic, copy) NSString *activeId;
@property(nonatomic) BOOL rewarded;
@property(nonatomic) BOOL initialized;
@property(nonatomic) BOOL initializing;
@property(nonatomic) BOOL loading;
@property(nonatomic) NSUInteger generation;
@property(nonatomic) BOOL consentFormOpen;
- (void)event:(NSString *)type request:(NSString *)request;
@end

static UIViewController *ads_controller() {
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if (scene.activationState != UISceneActivationStateForegroundActive || ![scene isKindOfClass:UIWindowScene.class]) continue;
        for (UIWindow *window in ((UIWindowScene *)scene).windows) {
            if (!window.isKeyWindow) continue;
            UIViewController *controller = window.rootViewController;
            while (controller.presentedViewController) controller = controller.presentedViewController;
            return controller;
        }
    }
    return nil;
}

@implementation DungeonAdsDelegate
- (instancetype)init {
    if ((self = [super init])) { _events = [NSMutableArray array]; _activeId = @""; }
    return self;
}
- (void)event:(NSString *)type request:(NSString *)request {
    @synchronized(self.events) { [self.events addObject:@{@"type":type, @"id":request ?: @""}]; }
}
- (void)didFinishLoadingADWithPlacementID:(NSString *)placementID { self.loading = NO; [self event:@"ready" request:@""]; }
- (void)didFailToLoadADWithPlacementID:(NSString *)placementID error:(NSError *)error { self.loading = NO; [self event:@"load_failed" request:@""]; }
- (void)rewardedVideoDidRewardSuccessForPlacemenID:(NSString *)placementID extra:(NSDictionary *)extra {
    if (self.activeId.length && !self.rewarded) { self.rewarded = YES; [self event:@"reward" request:self.activeId]; }
}
- (void)rewardedVideoDidCloseForPlacementID:(NSString *)placementID rewarded:(BOOL)rewarded extra:(NSDictionary *)extra {
    if (self.activeId.length) [self event:@"closed" request:self.activeId];
    self.activeId = @"";
}
- (void)rewardedVideoDidFailToPlayForPlacementID:(NSString *)placementID error:(NSError *)error extra:(NSDictionary *)extra {
    if (self.activeId.length) [self event:@"show_failed" request:self.activeId];
    self.activeId = @"";
}
- (void)rewardedVideoDidStartPlayingForPlacementID:(NSString *)placementID extra:(NSDictionary *)extra {}
- (void)rewardedVideoDidEndPlayingForPlacementID:(NSString *)placementID extra:(NSDictionary *)extra {}
- (void)rewardedVideoDidClickForPlacementID:(NSString *)placementID extra:(NSDictionary *)extra {}
@end

class DungeonAds : public Object {
    GDCLASS(DungeonAds, Object);
    DungeonAdsDelegate *__strong delegate;
protected:
    static void _bind_methods() {
        ClassDB::bind_method(D_METHOD("configure", "app_id", "app_key", "placement"), &DungeonAds::configure);
        ClassDB::bind_method(D_METHOD("load_rewarded"), &DungeonAds::load_rewarded);
        ClassDB::bind_method(D_METHOD("show_rewarded", "request_id", "scene"), &DungeonAds::show_rewarded);
        ClassDB::bind_method(D_METHOD("poll_events"), &DungeonAds::poll_events);
        ClassDB::bind_method(D_METHOD("privacy_options"), &DungeonAds::privacy_options);
        ClassDB::bind_method(D_METHOD("reset_preparation"), &DungeonAds::reset_preparation);
    }
public:
    DungeonAds() { delegate = [[DungeonAdsDelegate alloc] init]; }
    void configure(String app_id, String app_key, String placement) {
        NSString *app = [NSString stringWithUTF8String:app_id.utf8().get_data()];
        NSString *key = [NSString stringWithUTF8String:app_key.utf8().get_data()];
        NSString *unit = [NSString stringWithUTF8String:placement.utf8().get_data()];
        DungeonAdsDelegate *state = delegate;
        dispatch_async(dispatch_get_main_queue(), ^{
            if (state.initialized) { [state event:@"initialized" request:@""]; return; }
            if (state.initializing) return;
            if (state.consentFormOpen) { [state event:@"init_failed" request:@""]; return; }
            state.initializing = YES;
            NSUInteger attempt = state.generation;
            state.placement = unit;
            void (^initialize)(void) = ^{
                if (attempt != state.generation) return;
                if (!UMPConsentInformation.sharedInstance.canRequestAds) {
                    state.initializing = NO; [state event:@"init_failed" request:@""]; return;
                }
                NSError *error = nil;
                [[ATAPI sharedInstance] startWithAppID:app appKey:key error:&error];
                state.initializing = NO;
                state.initialized = error == nil;
                [state event:error ? @"init_failed" : @"initialized" request:@""];
            };
            [UMPConsentInformation.sharedInstance requestConsentInfoUpdateWithParameters:[[UMPRequestParameters alloc] init] completionHandler:^(NSError *error) {
                if (attempt != state.generation) return;
                if (error) { initialize(); return; }
                state.consentFormOpen = YES;
                [UMPConsentForm loadAndPresentIfRequiredFromViewController:ads_controller() completionHandler:^(NSError *formError) {
                    state.consentFormOpen = NO;
                    initialize();
                }];
            }];
        });
    }
    void load_rewarded() {
        DungeonAdsDelegate *state = delegate;
        dispatch_async(dispatch_get_main_queue(), ^{
            if (!state.initialized || !UMPConsentInformation.sharedInstance.canRequestAds) { [state event:@"load_failed" request:@""]; return; }
            if ([[ATAdManager sharedManager] rewardedVideoReadyForPlacementID:state.placement]) { [state event:@"ready" request:@""]; return; }
            if (!state.loading && !state.activeId.length) {
                state.loading = YES;
                [[ATAdManager sharedManager] loadADWithPlacementID:state.placement extra:@{} delegate:state];
            }
        });
    }
    void reset_preparation() {
        DungeonAdsDelegate *state = delegate;
        dispatch_async(dispatch_get_main_queue(), ^{
            if (state.activeId.length) return;
            state.generation++;
            state.initializing = NO;
            state.loading = NO;
        });
    }
    void show_rewarded(String request_id, String scene) {
        NSString *request = [NSString stringWithUTF8String:request_id.utf8().get_data()];
        DungeonAdsDelegate *state = delegate;
        dispatch_async(dispatch_get_main_queue(), ^{
            UIViewController *controller = ads_controller();
            if (!controller || state.activeId.length || !UMPConsentInformation.sharedInstance.canRequestAds || ![[ATAdManager sharedManager] rewardedVideoReadyForPlacementID:state.placement]) {
                [state event:@"show_failed" request:request]; return;
            }
            state.activeId = request;
            state.rewarded = NO;
            ATShowConfig *config = [[ATShowConfig alloc] initWithScene:@"" showCustomExt:@""];
            [[ATAdManager sharedManager] showRewardedVideoWithPlacementID:state.placement config:config inViewController:controller delegate:state];
        });
    }
    String poll_events() {
        @synchronized(delegate.events) {
            NSData *data = [NSJSONSerialization dataWithJSONObject:delegate.events options:0 error:nil];
            [delegate.events removeAllObjects];
            NSString *json = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
            return String::utf8(json.UTF8String ?: "[]");
        }
    }
    void privacy_options() {
        dispatch_async(dispatch_get_main_queue(), ^{
            [UMPConsentForm presentPrivacyOptionsFormFromViewController:ads_controller() completionHandler:^(NSError *error) {}];
        });
    }
};

static DungeonAds *singleton = nullptr;
void dungeon_ads_initialize() {
    ClassDB::register_class<DungeonAds>();
    singleton = memnew(DungeonAds);
    Engine::get_singleton()->add_singleton(Engine::Singleton("DungeonAds", singleton));
}
void dungeon_ads_deinitialize() {
    Engine::get_singleton()->remove_singleton("DungeonAds");
    memdelete(singleton);
    singleton = nullptr;
}
