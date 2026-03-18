// VLCrawler – Tweak.x

#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import "VLCrawler.h"

#define kVLCButtonTag  0x564C43
#define kVLCBadgeTag   0x424447

// ─── Forward declarations ───────────────────

@interface VLCrawlerSettingsVC : UITableViewController
@end

@interface VLCrawlerResultsVC : UITableViewController
- (instancetype)initWithResults:(NSArray<VLVideoResult *> *)results title:(NSString *)title;
@end

// SourcesViewController – used to detect when Sources tab is active
@interface _TtC7VidList21SourcesViewController : UIViewController
- (void)_vlc_ensureWindowButton;
- (void)_vlc_openCrawler:(UIButton *)sender;
@end

// ─────────────────────────────────────────────
// Button helpers – lives on the key window so
// nothing in the VC hierarchy can cover it
// ─────────────────────────────────────────────

static UIButton *VLCGetOrCreateButton(void) {
    UIWindow *win = nil;
    for (UIScene *scene in [UIApplication sharedApplication].connectedScenes) {
        if ([scene isKindOfClass:[UIWindowScene class]]) {
            for (UIWindow *w in ((UIWindowScene *)scene).windows) {
                if (w.isKeyWindow) { win = w; break; }
            }
        }
    }
    if (!win) win = [UIApplication sharedApplication].keyWindow;
    if (!win) return nil;

    // Find existing
    for (UIView *v in win.subviews) {
        if (v.tag == kVLCButtonTag) return (UIButton *)v;
    }

    // Create
    CGFloat size   = 54;
    CGFloat margin = 20;
    CGFloat safeB  = win.safeAreaInsets.bottom;
    CGFloat tabH   = 49 + safeB;

    UIButton *btn = [UIButton buttonWithType:UIButtonTypeSystem];
    btn.tag       = kVLCButtonTag;
    btn.frame     = CGRectMake(win.bounds.size.width  - size - margin,
                               win.bounds.size.height - size - tabH - margin,
                               size, size);
    btn.autoresizingMask = UIViewAutoresizingFlexibleTopMargin | UIViewAutoresizingFlexibleLeftMargin;

    btn.backgroundColor     = [UIColor systemBlueColor];
    btn.layer.cornerRadius  = size / 2.0;
    btn.layer.shadowColor   = [UIColor blackColor].CGColor;
    btn.layer.shadowOpacity = 0.35f;
    btn.layer.shadowRadius  = 8;
    btn.layer.shadowOffset  = CGSizeMake(0, 4);
    btn.tintColor           = [UIColor whiteColor];

    UIImageSymbolConfiguration *cfg =
        [UIImageSymbolConfiguration configurationWithPointSize:22
                                                        weight:UIImageSymbolWeightMedium];
    UIImage *icon = [UIImage systemImageNamed:@"antenna.radiowaves.left.and.right"
                            withConfiguration:cfg];
    [btn setImage:icon forState:UIControlStateNormal];
    btn.hidden = YES; // shown only when Sources tab is visible

    // Badge
    NSUInteger count = [[VLCrawler shared] allCachedResults].count;
    if (count) {
        UILabel *badge            = [[UILabel alloc] initWithFrame:CGRectMake(34, -4, 22, 18)];
        badge.tag                 = kVLCBadgeTag;
        badge.backgroundColor     = [UIColor systemRedColor];
        badge.textColor           = [UIColor whiteColor];
        badge.font                = [UIFont boldSystemFontOfSize:10];
        badge.textAlignment       = NSTextAlignmentCenter;
        badge.layer.cornerRadius  = 9;
        badge.layer.masksToBounds = YES;
        badge.text = count > 99 ? @"99+" : [NSString stringWithFormat:@"%lu", (unsigned long)count];
        [btn addSubview:badge];
    }

    [win addSubview:btn];
    return btn;
}

// ─────────────────────────────────────────────
// Hook: SourcesViewController
// Show button when Sources is on screen, hide when leaving
// ─────────────────────────────────────────────

%hook _TtC7VidList21SourcesViewController

- (void)viewDidAppear:(BOOL)animated {
    %orig;
    [self _vlc_ensureWindowButton];
}

- (void)viewWillDisappear:(BOOL)animated {
    %orig;
    UIButton *btn = VLCGetOrCreateButton();
    btn.hidden = YES;
}

%new
- (void)_vlc_ensureWindowButton {
    UIButton *btn = VLCGetOrCreateButton();
    if (!btn) return;
    // Wire target if not already set (button may have been created without a target)
    [btn removeTarget:nil action:NULL forControlEvents:UIControlEventTouchUpInside];
    [btn addTarget:self
            action:@selector(_vlc_openCrawler:)
  forControlEvents:UIControlEventTouchUpInside];
    btn.hidden = NO;
}

%new
- (void)_vlc_openCrawler:(UIButton *)sender {
    UIViewController *top = self;
    // Walk up to find presentable VC
    while (top.presentedViewController) top = top.presentedViewController;

    VLCrawlerSettingsVC *vc = [[VLCrawlerSettingsVC alloc] initWithStyle:UITableViewStyleInsetGrouped];
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:vc];
    nav.modalPresentationStyle = UIModalPresentationFormSheet;
    if (@available(iOS 15.0, *)) {
        UISheetPresentationController *sheet = nav.sheetPresentationController;
        sheet.detents = @[UISheetPresentationControllerDetent.largeDetent];
        sheet.prefersGrabberVisible = YES;
    }
    [top presentViewController:nav animated:YES completion:nil];
}

%end

// ─────────────────────────────────────────────
// Premium JSON patcher
// Handles all vidlist.pw responses:
//   v1/auth/refreshToken  → patches isPremium, isTrial, premiumExpire
//   v2/premium/subscriptions → patches isActive, expireAt
//   Any other endpoint    → same deep walk
// ─────────────────────────────────────────────

static void VLCPatchDictRecursive(id obj);

static void VLCPatchDictRecursive(id obj) {
    if ([obj isKindOfClass:[NSMutableDictionary class]]) {
        NSMutableDictionary *d = (NSMutableDictionary *)obj;

        // Auth / profile fields
        if (d[@"isPremium"]     != nil) d[@"isPremium"]     = @YES;
        if (d[@"isTrial"]       != nil) d[@"isTrial"]       = @NO;
        if (d[@"premiumExpire"] != nil) d[@"premiumExpire"] = @"2099-12-31T00:00:00.000Z";

        // Subscription object fields
        if (d[@"isActive"]  != nil) d[@"isActive"]  = @YES;
        if (d[@"expireAt"]  != nil) d[@"expireAt"]  = @"2099-12-31T00:00:00.000Z";
        if (d[@"expiredAt"] != nil) d[@"expiredAt"] = @"2099-12-31T00:00:00.000Z";

        // success wrapper sometimes has isPremium at top level
        if (d[@"success"] != nil && [d[@"success"] isKindOfClass:[NSMutableDictionary class]]) {
            VLCPatchDictRecursive(d[@"success"]);
        }

        for (id key in [d allKeys]) {
            VLCPatchDictRecursive(d[key]);
        }

    } else if ([obj isKindOfClass:[NSMutableArray class]]) {
        for (id item in (NSMutableArray *)obj) {
            VLCPatchDictRecursive(item);
        }
    }
}

static NSData *VLCPatchPremiumJSON(NSData *data, NSString *path) {
    if (!data || data.length < 10) return data;

    // Only bother parsing JSON for relevant endpoints
    BOOL relevant = [path containsString:@"auth"]
                 || [path containsString:@"premium"]
                 || [path containsString:@"profile"]
                 || [path containsString:@"user"];

    if (!relevant) {
        // Quick string check before expensive parse
        NSString *body = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
        if (!body) return data;
        if ([body rangeOfString:@"isPremium"].location  == NSNotFound &&
            [body rangeOfString:@"isActive"].location   == NSNotFound &&
            [body rangeOfString:@"expireAt"].location   == NSNotFound) {
            return data;
        }
    }

    NSError *err = nil;
    id json = [NSJSONSerialization JSONObjectWithData:data
                                             options:NSJSONReadingMutableContainers
                                               error:&err];
    if (err || !json) return data;

    VLCPatchDictRecursive(json);

    NSData *out = [NSJSONSerialization dataWithJSONObject:json options:0 error:&err];
    return (err || !out) ? data : out;
}

%hook NSURLSession

- (NSURLSessionDataTask *)dataTaskWithRequest:(NSURLRequest *)request
                            completionHandler:(void (^)(NSData *, NSURLResponse *, NSError *))completion {
    NSString *host = request.URL.host ?: @"";
    if (![host containsString:@"vidlist.pw"]) {
        return %orig(request, completion);
    }
    NSString *path = request.URL.path ?: @"";
    void (^patchedHandler)(NSData *, NSURLResponse *, NSError *) =
        ^(NSData *data, NSURLResponse *response, NSError *error) {
            if (completion) completion(VLCPatchPremiumJSON(data, path), response, error);
        };
    return %orig(request, patchedHandler);
}

%end

// ─────────────────────────────────────────────
// Constructor
// ─────────────────────────────────────────────

%ctor {
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0), ^{
        (void)[VLCrawler shared];
    });
}
