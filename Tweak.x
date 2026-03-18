// VLCrawler – Tweak.x

#import <UIKit/UIKit.h>
#import "VLCrawler.h"

// Tag values for our injected views (valid integer literals)
#define kVLCButtonTag  0x564C43   // "VLC"
#define kVLCBadgeTag   0x424447   // "BDG"

// Forward declare our VCs
@interface VLCrawlerSettingsVC : UITableViewController
@end
@interface VLCrawlerResultsVC : UITableViewController
- (instancetype)initWithResults:(NSArray<VLVideoResult *> *)results title:(NSString *)title;
@end

// Full interface declaration so Logos can see properties/methods on self
@interface _TtC7VidList21SourcesViewController : UIViewController
@end

// ─────────────────────────────────────────────
// Hook SourcesViewController
// ─────────────────────────────────────────────

%hook _TtC7VidList21SourcesViewController

- (void)viewDidLoad {
    %orig;
    [self _vlc_injectCrawlerButton];
}

- (void)viewWillAppear:(BOOL)animated {
    %orig;
    BOOL found = NO;
    for (UIView *v in self.view.subviews) {
        if (v.tag == kVLCButtonTag) { found = YES; break; }
    }
    if (!found) [self _vlc_injectCrawlerButton];
}

%new
- (void)_vlc_injectCrawlerButton {
    // Remove any stale instance
    for (UIView *v in self.view.subviews) {
        if (v.tag == kVLCButtonTag) [v removeFromSuperview];
    }

    CGFloat size   = 54;
    CGFloat margin = 20;
    CGRect  bounds = self.view.bounds;

    UIButton *btn  = [UIButton buttonWithType:UIButtonTypeSystem];
    btn.tag        = kVLCButtonTag;
    btn.frame      = CGRectMake(bounds.size.width  - size - margin,
                                bounds.size.height - size - margin - 80,
                                size, size);
    btn.autoresizingMask = UIViewAutoresizingFlexibleTopMargin | UIViewAutoresizingFlexibleLeftMargin;

    btn.backgroundColor    = [UIColor systemBlueColor];
    btn.layer.cornerRadius = size / 2.0;
    btn.layer.shadowColor  = [UIColor blackColor].CGColor;
    btn.layer.shadowOpacity = 0.25f;
    btn.layer.shadowRadius  = 6;
    btn.layer.shadowOffset  = CGSizeMake(0, 3);
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

    [self.view addSubview:btn];
    [self.view bringSubviewToFront:btn];
}

%new
- (void)_vlc_updateBadge:(UIButton *)btn {
    NSArray *allCached = [[VLCrawler shared] allCachedResults];

    // Remove old badge
    for (UIView *v in btn.subviews) {
        if (v.tag == kVLCBadgeTag) [v removeFromSuperview];
    }

    if (!allCached.count) return;

    UILabel *badge         = [[UILabel alloc] initWithFrame:CGRectMake(btn.bounds.size.width - 18, -4, 22, 18)];
    badge.tag              = kVLCBadgeTag;
    badge.backgroundColor  = [UIColor systemRedColor];
    badge.textColor        = [UIColor whiteColor];
    badge.font             = [UIFont boldSystemFontOfSize:10];
    badge.textAlignment    = NSTextAlignmentCenter;
    badge.layer.cornerRadius  = 9;
    badge.layer.masksToBounds = YES;
    badge.text = allCached.count > 99
        ? @"99+"
        : [NSString stringWithFormat:@"%lu", (unsigned long)allCached.count];

    [btn addSubview:badge];
}

%new
- (void)_vlc_openCrawler:(UIButton *)sender {
    VLCrawlerSettingsVC *vc  = [[VLCrawlerSettingsVC alloc] initWithStyle:UITableViewStyleInsetGrouped];
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:vc];
    nav.modalPresentationStyle  = UIModalPresentationFormSheet;
    if (@available(iOS 15.0, *)) {
        UISheetPresentationController *sheet = nav.sheetPresentationController;
        sheet.detents = @[UISheetPresentationControllerDetent.largeDetent];
        sheet.prefersGrabberVisible = YES;
    }
    [self presentViewController:nav animated:YES completion:nil];
}

%end

// ─────────────────────────────────────────────
// Constructor – warm up cache on launch
// ─────────────────────────────────────────────

%ctor {
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0), ^{
        (void)[VLCrawler shared];
    });
}
