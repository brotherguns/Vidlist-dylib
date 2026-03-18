// VLCrawler – Tweak.x
// Hooks into VidList (com.vh.vhub) to inject a "My Sources / Crawler" entry
// into the SourcesViewController.

#import <UIKit/UIKit.h>
#import "VLCrawler.h"

// Forward declare our VCs (defined in their respective .m files)
@interface VLCrawlerSettingsVC : UITableViewController
@end
@interface VLCrawlerResultsVC : UITableViewController
- (instancetype)initWithResults:(NSArray<VLVideoResult *> *)results title:(NSString *)title;
@end

// ─────────────────────────────────────────────
// Hook SourcesViewController
// Mangled Swift name: _TtC7VidList21SourcesViewController
// ─────────────────────────────────────────────

%hook _TtC7VidList21SourcesViewController

- (void)viewDidLoad {
    %orig;
    [self _vlc_injectCrawlerButton];
}

// Also catch viewWillAppear to re-add if removed on nav push/pop
- (void)viewWillAppear:(BOOL)animated {
    %orig;
    // Make sure button still exists
    BOOL found = NO;
    for (UIView *v in self.view.subviews) {
        if (v.tag == 0xVLC) { found = YES; break; }
    }
    if (!found) [self _vlc_injectCrawlerButton];
}

%new
- (void)_vlc_injectCrawlerButton {
    // Remove any existing one
    for (UIView *v in self.view.subviews) {
        if (v.tag == 0xVLC) [v removeFromSuperview];
    }

    // Floating action button in bottom-right
    CGFloat size = 54;
    CGFloat margin = 20;
    UIButton *btn = [UIButton buttonWithType:UIButtonTypeSystem];
    btn.tag = 0xVLC;

    // Position – will be re-adjusted in viewDidLayoutSubviews override
    CGRect frame = self.view.bounds;
    btn.frame = CGRectMake(frame.size.width  - size - margin,
                           frame.size.height - size - margin - 80, // above tab bar
                           size, size);
    btn.autoresizingMask = UIViewAutoresizingFlexibleTopMargin | UIViewAutoresizingFlexibleLeftMargin;

    // Style
    btn.backgroundColor = [UIColor systemBlueColor];
    btn.layer.cornerRadius = size / 2;
    btn.layer.shadowColor = [UIColor blackColor].CGColor;
    btn.layer.shadowOpacity = 0.25;
    btn.layer.shadowRadius = 6;
    btn.layer.shadowOffset = CGSizeMake(0, 3);
    btn.tintColor = [UIColor whiteColor];

    UIImageSymbolConfiguration *cfg = [UIImageSymbolConfiguration
        configurationWithPointSize:22 weight:UIImageSymbolWeightMedium];
    UIImage *icon = [UIImage systemImageNamed:@"antenna.radiowaves.left.and.right"
                            withConfiguration:cfg];
    [btn setImage:icon forState:UIControlStateNormal];

    // Badge showing cached count if any
    [self _vlc_updateBadge:btn];

    [btn addTarget:self action:@selector(_vlc_openCrawler:) forControlEvents:UIControlEventTouchUpInside];

    [self.view addSubview:btn];
    [self.view bringSubviewToFront:btn];
}

%new
- (void)_vlc_updateBadge:(UIButton *)btn {
    NSArray *allCached = [[VLCrawler shared] allCachedResults];
    if (!allCached.count) return;

    // Small red badge
    UILabel *badge = [[UILabel alloc] initWithFrame:CGRectMake(btn.bounds.size.width - 18, -4, 22, 18)];
    badge.tag = 0xBADGE;
    badge.backgroundColor  = [UIColor systemRedColor];
    badge.textColor        = [UIColor whiteColor];
    badge.font             = [UIFont boldSystemFontOfSize:10];
    badge.textAlignment    = NSTextAlignmentCenter;
    badge.layer.cornerRadius  = 9;
    badge.layer.masksToBounds = YES;
    badge.text = allCached.count > 99 ? @"99+" : [NSString stringWithFormat:@"%lu", (unsigned long)allCached.count];

    // Remove old badge
    for (UIView *v in btn.subviews) {
        if (v.tag == 0xBADGE) [v removeFromSuperview];
    }
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
// Constructor – pre-load cache on app start
// ─────────────────────────────────────────────

%ctor {
    // Warm up the crawler singleton (loads cache from disk)
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0), ^{
        (void)[VLCrawler shared];
    });
}
