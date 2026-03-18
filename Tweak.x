// VLCrawler – Tweak.x
// Fix 1: inject button onto TabBarController.view (always on top)
// Fix 2: intercept NSURLSession completions, patch isPremium/isTrial in JSON

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

@interface _TtC7VidList16TabBarController : UITabBarController
- (void)_vlc_injectButton;
- (void)_vlc_updateBadge:(UIButton *)btn;
- (void)_vlc_openCrawler:(UIButton *)sender;
@end

// ─────────────────────────────────────────────
// Hook 1: TabBarController
// Button lives here so it floats above every tab's content view
// ─────────────────────────────────────────────

%hook _TtC7VidList16TabBarController

- (void)viewDidLoad {
    %orig;
    [self _vlc_injectButton];
}

- (void)viewDidLayoutSubviews {
    %orig;
    for (UIView *v in self.view.subviews) {
        if (v.tag == kVLCButtonTag) {
            [self.view bringSubviewToFront:v];
            break;
        }
    }
}

- (void)setSelectedIndex:(NSUInteger)index {
    %orig;
    for (UIView *v in self.view.subviews) {
        if (v.tag == kVLCButtonTag) {
            ((UIButton *)v).hidden = (index != 2);
            break;
        }
    }
}

%new
- (void)_vlc_injectButton {
    for (UIView *v in self.view.subviews) {
        if (v.tag == kVLCButtonTag) [v removeFromSuperview];
    }

    CGFloat size   = 54;
    CGFloat margin = 20;
    CGFloat tabH   = self.tabBar.frame.size.height ?: 83;
    CGRect  bounds = self.view.bounds;

    UIButton *btn = [UIButton buttonWithType:UIButtonTypeSystem];
    btn.tag       = kVLCButtonTag;
    btn.frame     = CGRectMake(bounds.size.width  - size - margin,
                               bounds.size.height - size - tabH - margin,
                               size, size);
    btn.autoresizingMask = UIViewAutoresizingFlexibleTopMargin | UIViewAutoresizingFlexibleLeftMargin;

    btn.backgroundColor     = [UIColor systemBlueColor];
    btn.layer.cornerRadius  = size / 2.0;
    btn.layer.shadowColor   = [UIColor blackColor].CGColor;
    btn.layer.shadowOpacity = 0.3f;
    btn.layer.shadowRadius  = 8;
    btn.layer.shadowOffset  = CGSizeMake(0, 4);
    btn.tintColor           = [UIColor whiteColor];

    UIImageSymbolConfiguration *cfg =
        [UIImageSymbolConfiguration configurationWithPointSize:22
                                                        weight:UIImageSymbolWeightMedium];
    UIImage *icon = [UIImage systemImageNamed:@"antenna.radiowaves.left.and.right"
                            withConfiguration:cfg];
    [btn setImage:icon forState:UIControlStateNormal];

    [self _vlc_updateBadge:btn];
    [btn addTarget:self
            action:@selector(_vlc_openCrawler:)
  forControlEvents:UIControlEventTouchUpInside];

    btn.hidden = (self.selectedIndex != 2);

    [self.view addSubview:btn];
    [self.view bringSubviewToFront:btn];
}

%new
- (void)_vlc_updateBadge:(UIButton *)btn {
    for (UIView *v in btn.subviews) {
        if (v.tag == kVLCBadgeTag) [v removeFromSuperview];
    }
    NSUInteger count = [[VLCrawler shared] allCachedResults].count;
    if (!count) return;

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

%new
- (void)_vlc_openCrawler:(UIButton *)sender {
    VLCrawlerSettingsVC *vc = [[VLCrawlerSettingsVC alloc] initWithStyle:UITableViewStyleInsetGrouped];
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:vc];
    nav.modalPresentationStyle = UIModalPresentationFormSheet;
    if (@available(iOS 15.0, *)) {
        UISheetPresentationController *sheet = nav.sheetPresentationController;
        sheet.detents = @[UISheetPresentationControllerDetent.largeDetent];
        sheet.prefersGrabberVisible = YES;
    }
    [self presentViewController:nav animated:YES completion:nil];
}

%end

// ─────────────────────────────────────────────
// Hook 2: NSURLSession response patching
// Patches isPremium → true, isTrial → false in any vidlist.pw JSON response
// before Swift's JSONDecoder ever sees the bytes
// ─────────────────────────────────────────────

static NSData *VLCPatchPremiumJSON(NSData *data) {
    if (!data || data.length < 10) return data;

    NSString *body = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    if (!body) return data;
    if ([body rangeOfString:@"isPremium"].location == NSNotFound &&
        [body rangeOfString:@"isTrial"].location == NSNotFound) {
        return data;
    }

    NSError *err = nil;
    id json = [NSJSONSerialization JSONObjectWithData:data
                                             options:NSJSONReadingMutableContainers
                                               error:&err];
    if (err || !json) return data;

    __block BOOL patched = NO;
    void (^patchDict)(NSMutableDictionary *) = ^(NSMutableDictionary *d) {
        if (d[@"isPremium"]    != nil) { d[@"isPremium"]    = @YES;          patched = YES; }
        if (d[@"isTrial"]      != nil) { d[@"isTrial"]      = @NO;           patched = YES; }
        if (d[@"premiumExpire"] != nil) { d[@"premiumExpire"] = @"2099-12-31"; patched = YES; }
    };

    __block void (^walk)(id);
    walk = ^(id obj) {
        if ([obj isKindOfClass:[NSMutableDictionary class]]) {
            patchDict((NSMutableDictionary *)obj);
            for (id key in (NSMutableDictionary *)obj) walk(((NSMutableDictionary *)obj)[key]);
        } else if ([obj isKindOfClass:[NSMutableArray class]]) {
            for (id item in (NSMutableArray *)obj) walk(item);
        }
    };
    walk(json);

    if (!patched) return data;
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
    void (^patchedHandler)(NSData *, NSURLResponse *, NSError *) =
        ^(NSData *data, NSURLResponse *response, NSError *error) {
            if (completion) completion(VLCPatchPremiumJSON(data), response, error);
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
