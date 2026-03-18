// VLCrawler – Tweak.x
//
// • Floating overlay window (UIWindowLevelAlert+50) — always on top
// • Draggable pill button, expands to crawler sheet
// • Auto-hides during video playback (AVPlayerViewController)
// • Premium: patches NSURLSession JSON + UserDefaults cache + Swift ObjC bridge

#import <UIKit/UIKit.h>
#import <AVKit/AVKit.h>
#import <objc/runtime.h>
#import "VLCrawler.h"

#define kVLCButtonTag  0x564C43
#define kVLCBadgeTag   0x424447

// ─── Forward declarations ────────────────────────────────────────────────────

@interface VLCrawlerSettingsVC : UITableViewController
@end

// ─────────────────────────────────────────────────────────────────────────────
// VLCOverlayWindow – transparent pass-through window that only hits our button
// ─────────────────────────────────────────────────────────────────────────────

@interface VLCOverlayWindow : UIWindow
@end

@implementation VLCOverlayWindow

- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    UIView *hit = [super hitTest:point withEvent:event];
    // Pass through taps that don't land on our views
    if (hit == self.rootViewController.view || hit == self) return nil;
    return hit;
}

@end

// ─────────────────────────────────────────────────────────────────────────────
// VLCOverlayVC – root VC for the overlay window
// ─────────────────────────────────────────────────────────────────────────────

@interface VLCOverlayVC : UIViewController
@property (nonatomic, strong) UIButton  *fabButton;
@property (nonatomic, strong) UILabel   *badgeLabel;
@property (nonatomic, assign) CGPoint    lastPos;
- (void)refreshBadge;
- (void)showButton;
- (void)hideButton;
@end

@implementation VLCOverlayVC

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor clearColor];
    self.view.userInteractionEnabled = YES;
    [self _buildFAB];
}

- (void)_buildFAB {
    CGFloat size   = 52;
    CGFloat margin = 22;
    CGRect  screen = UIScreen.mainScreen.bounds;
    CGFloat safeB  = 0;
    if (@available(iOS 11.0, *)) {
        UIWindow *win = nil;
        for (UIScene *sc in UIApplication.sharedApplication.connectedScenes) {
            if ([sc isKindOfClass:[UIWindowScene class]]) {
                win = ((UIWindowScene *)sc).windows.firstObject;
                if (win) break;
            }
        }
        safeB = win.safeAreaInsets.bottom;
    }

    UIButton *btn = [UIButton buttonWithType:UIButtonTypeCustom];
    btn.tag   = kVLCButtonTag;
    btn.frame = CGRectMake(screen.size.width - size - margin,
                           screen.size.height - size - 49 - safeB - margin,
                           size, size);

    // Style – pill
    btn.backgroundColor    = [UIColor colorWithRed:0.13 green:0.13 blue:0.95 alpha:0.92];
    btn.layer.cornerRadius = size / 2.0;
    btn.layer.shadowColor  = [UIColor blackColor].CGColor;
    btn.layer.shadowOpacity= 0.40f;
    btn.layer.shadowRadius = 10;
    btn.layer.shadowOffset = CGSizeMake(0, 5);

    UIImageSymbolConfiguration *cfg =
        [UIImageSymbolConfiguration configurationWithPointSize:21
                                                        weight:UIImageSymbolWeightMedium];
    [btn setImage:[UIImage systemImageNamed:@"antenna.radiowaves.left.and.right"
                          withConfiguration:cfg]
         forState:UIControlStateNormal];
    btn.tintColor = [UIColor whiteColor];

    // Badge
    UILabel *badge        = [[UILabel alloc] initWithFrame:CGRectMake(32, -5, 22, 18)];
    badge.tag             = kVLCBadgeTag;
    badge.hidden          = YES;
    badge.backgroundColor = [UIColor systemRedColor];
    badge.textColor       = [UIColor whiteColor];
    badge.font            = [UIFont boldSystemFontOfSize:9];
    badge.textAlignment   = NSTextAlignmentCenter;
    badge.layer.cornerRadius  = 9;
    badge.layer.masksToBounds = YES;
    [btn addSubview:badge];
    self.badgeLabel = badge;

    // Drag gesture
    UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc]
        initWithTarget:self action:@selector(_handleDrag:)];
    [btn addGestureRecognizer:pan];

    [btn addTarget:self action:@selector(_fabTapped)
  forControlEvents:UIControlEventTouchUpInside];

    self.fabButton = btn;
    [self.view addSubview:btn];

    [self refreshBadge];
}

- (void)refreshBadge {
    NSUInteger n = [[VLCrawler shared] allCachedResults].count;
    self.badgeLabel.hidden = (n == 0);
    self.badgeLabel.text   = n > 99 ? @"99+" : [NSString stringWithFormat:@"%lu", (unsigned long)n];
}

- (void)showButton { self.fabButton.hidden = NO; }
- (void)hideButton { self.fabButton.hidden = YES; }

- (void)_handleDrag:(UIPanGestureRecognizer *)g {
    CGPoint delta = [g translationInView:self.view];
    CGRect  f     = self.fabButton.frame;
    f.origin.x   += delta.x;
    f.origin.y   += delta.y;
    self.fabButton.frame = f;
    [g setTranslation:CGPointZero inView:self.view];

    if (g.state == UIGestureRecognizerStateEnded) {
        // Snap to nearest edge
        CGRect  bounds = self.view.bounds;
        CGFloat midX   = CGRectGetMidX(f);
        CGFloat targetX = midX < bounds.size.width / 2
            ? 16
            : bounds.size.width - f.size.width - 16;
        [UIView animateWithDuration:0.3
                              delay:0
             usingSpringWithDamping:0.7
              initialSpringVelocity:0.5
                            options:UIViewAnimationOptionCurveEaseOut
                         animations:^{ 
                             CGRect nf = self.fabButton.frame;
                             nf.origin.x = targetX;
                             self.fabButton.frame = nf;
                         } completion:nil];
    }
}

- (void)_fabTapped {
    // Find top-most presented VC in the main app window
    UIViewController *top = nil;
    for (UIScene *sc in UIApplication.sharedApplication.connectedScenes) {
        if ([sc isKindOfClass:[UIWindowScene class]]) {
            for (UIWindow *w in ((UIWindowScene *)sc).windows) {
                if (w != self.view.window && [w isKeyWindow]) {
                    top = w.rootViewController;
                    while (top.presentedViewController) top = top.presentedViewController;
                    break;
                }
            }
        }
    }
    // Fallback: use overlay window itself
    if (!top) {
        top = self;
    }

    VLCrawlerSettingsVC *vc  = [[VLCrawlerSettingsVC alloc] initWithStyle:UITableViewStyleInsetGrouped];
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:vc];
    nav.modalPresentationStyle = UIModalPresentationFormSheet;
    if (@available(iOS 15.0, *)) {
        UISheetPresentationController *sheet = nav.sheetPresentationController;
        sheet.detents = @[UISheetPresentationControllerDetent.mediumDetent,
                          UISheetPresentationControllerDetent.largeDetent];
        sheet.prefersGrabberVisible = YES;
    }
    [top presentViewController:nav animated:YES completion:nil];
}

@end

// ─────────────────────────────────────────────────────────────────────────────
// Singleton accessor
// ─────────────────────────────────────────────────────────────────────────────

static VLCOverlayWindow *gOverlayWindow = nil;
static VLCOverlayVC     *gOverlayVC     = nil;

static void VLCSetupOverlay(void) {
    if (gOverlayWindow) return;

    dispatch_async(dispatch_get_main_queue(), ^{
        UIWindowScene *scene = nil;
        for (UIScene *sc in UIApplication.sharedApplication.connectedScenes) {
            if ([sc isKindOfClass:[UIWindowScene class]] &&
                sc.activationState == UISceneActivationStateForegroundActive) {
                scene = (UIWindowScene *)sc;
                break;
            }
        }
        if (!scene) return;

        gOverlayVC             = [[VLCOverlayVC alloc] init];
        gOverlayWindow         = [[VLCOverlayWindow alloc] initWithWindowScene:scene];
        gOverlayWindow.rootViewController = gOverlayVC;
        gOverlayWindow.windowLevel        = UIWindowLevelAlert + 50;
        gOverlayWindow.backgroundColor    = [UIColor clearColor];
        gOverlayWindow.hidden             = NO;
        [gOverlayWindow makeKeyAndVisible];
        // Don't steal key status from main app
        [gOverlayWindow resignFirstResponder];
    });
}

// ─────────────────────────────────────────────────────────────────────────────
// Hook: AVPlayerViewController – hide/show FAB during video playback
// ─────────────────────────────────────────────────────────────────────────────

%hook AVPlayerViewController

- (void)viewWillAppear:(BOOL)animated {
    %orig;
    [gOverlayVC hideButton];
}

- (void)viewWillDisappear:(BOOL)animated {
    %orig;
    [gOverlayVC showButton];
    [gOverlayVC refreshBadge];
}

%end

// ─────────────────────────────────────────────────────────────────────────────
// Premium JSON patcher
// ─────────────────────────────────────────────────────────────────────────────

static void VLCPatchDictRecursive(id obj) {
    if ([obj isKindOfClass:[NSMutableDictionary class]]) {
        NSMutableDictionary *d = (NSMutableDictionary *)obj;
        if (d[@"isPremium"]     != nil) d[@"isPremium"]     = @YES;
        if (d[@"isTrial"]       != nil) d[@"isTrial"]       = @NO;
        if (d[@"premiumExpire"] != nil) d[@"premiumExpire"] = @"2099-12-31T00:00:00.000Z";
        if (d[@"isActive"]      != nil) d[@"isActive"]      = @YES;
        if (d[@"expireAt"]      != nil) d[@"expireAt"]      = @"2099-12-31T00:00:00.000Z";
        if (d[@"expiredAt"]     != nil) d[@"expiredAt"]      = @"2099-12-31T00:00:00.000Z";
        // Some APIs wrap data under "data" or "result" or "success" keys
        for (id key in [d allKeys]) VLCPatchDictRecursive(d[key]);
    } else if ([obj isKindOfClass:[NSMutableArray class]]) {
        for (id item in (NSMutableArray *)obj) VLCPatchDictRecursive(item);
    }
}

static NSData *VLCPatchJSON(NSData *data) {
    if (!data || data.length < 4) return data;
    // Only process JSON (starts with { or [)
    uint8_t first = ((uint8_t *)data.bytes)[0];
    if (first != '{' && first != '[') return data;

    NSError *err = nil;
    id json = [NSJSONSerialization JSONObjectWithData:data
                                             options:NSJSONReadingMutableContainers
                                               error:&err];
    if (err || !json) return data;
    VLCPatchDictRecursive(json);
    NSData *out = [NSJSONSerialization dataWithJSONObject:json options:0 error:&err];
    return (err || !out) ? data : out;
}

// ─────────────────────────────────────────────────────────────────────────────
// Hook: NSURLSession – patch all vidlist.pw responses
// ─────────────────────────────────────────────────────────────────────────────

// ─────────────────────────────────────────────────────────────────────────────
// VLCDumpProtocol – NSURLProtocol subclass
// Registered globally, catches ALL vidlist.pw traffic including Alamofire
// delegate sessions that bypass NSURLSession completion handler hooks
// ─────────────────────────────────────────────────────────────────────────────

static NSString *VLCDumpPath(void) {
    NSString *docs = NSSearchPathForDirectoriesInDomains(
        NSDocumentDirectory, NSUserDomainMask, YES).firstObject;
    // Write to Documents root so it shows in Files app immediately
    return docs;
}

static void VLCSaveDump(NSData *raw, NSString *urlPath) {
    if (!raw || raw.length < 4) return;
    uint8_t first = ((uint8_t *)raw.bytes)[0];
    if (first != '{' && first != '[') return;   // not JSON, skip

    NSString *dumpDir = [VLCDumpPath() stringByAppendingPathComponent:@"VLDumps"];
    [[NSFileManager defaultManager] createDirectoryAtPath:dumpDir
                              withIntermediateDirectories:YES
                                               attributes:nil
                                                    error:nil];

    // Slug from path
    NSString *slug = [urlPath stringByReplacingOccurrencesOfString:@"/" withString:@"_"];
    if (slug.length > 50) slug = [slug substringFromIndex:slug.length - 50];
    long long ts = (long long)[[NSDate date] timeIntervalSince1970];

    // Pretty print
    NSError *e = nil;
    id obj = [NSJSONSerialization JSONObjectWithData:raw options:0 error:&e];
    NSData *pretty = (obj && !e)
        ? [NSJSONSerialization dataWithJSONObject:obj options:NSJSONWritingPrettyPrinted error:nil]
        : raw;

    NSString *name = [NSString stringWithFormat:@"%lld%@.json", ts, slug];
    NSString *full = [dumpDir stringByAppendingPathComponent:name];
    [pretty writeToFile:full atomically:YES];
    NSLog(@"[VLCrawler] Dumped %lu bytes → %@", (unsigned long)raw.length, name);
}

@interface VLCDumpProtocol : NSURLProtocol
@property (nonatomic, strong) NSURLSessionDataTask *innerTask;
@property (nonatomic, strong) NSMutableData        *buffer;
@end

@implementation VLCDumpProtocol

+ (BOOL)canInitWithRequest:(NSURLRequest *)request {
    if ([NSURLProtocol propertyForKey:@"VLCDone" inRequest:request]) return NO;
    NSString *host = request.URL.host ?: @"";
    return [host containsString:@"vidlist.pw"];
}

+ (NSURLRequest *)canonicalRequestForRequest:(NSURLRequest *)request {
    return request;
}

- (void)startLoading {
    self.buffer = [NSMutableData data];

    NSMutableURLRequest *req = [self.request mutableCopy];
    [NSURLProtocol setProperty:@YES forKey:@"VLCDone" inRequest:req];

    __weak VLCDumpProtocol *weakSelf = self;
    NSURLSession *session = [NSURLSession sessionWithConfiguration:
        [NSURLSessionConfiguration defaultSessionConfiguration]];

    self.innerTask = [session dataTaskWithRequest:req
                               completionHandler:^(NSData *data, NSURLResponse *resp, NSError *err) {
        VLCDumpProtocol *s = weakSelf;
        if (!s) return;

        if (err) {
            [s.client URLProtocol:s didFailWithError:err];
            return;
        }

        NSHTTPURLResponse *httpResp = (NSHTTPURLResponse *)resp;
        [s.client URLProtocol:s didReceiveResponse:httpResp
               cacheStoragePolicy:NSURLCacheStorageNotAllowed];

        // Dump raw before patching
        VLCSaveDump(data, s.request.URL.path ?: @"unknown");

        // Patch and forward
        NSData *patched = VLCPatchJSON(data);
        if (patched.length) [s.client URLProtocol:s didLoadData:patched];
        [s.client URLProtocolDidFinishLoading:s];
    }];
    [self.innerTask resume];
}

- (void)stopLoading {
    [self.innerTask cancel];
}

@end

%hook NSURLSession

- (NSURLSessionDataTask *)dataTaskWithRequest:(NSURLRequest *)request
                            completionHandler:(void (^)(NSData *, NSURLResponse *, NSError *))completion {
    NSString *host = request.URL.host ?: @"";
    if (![host containsString:@"vidlist.pw"]) {
        return %orig(request, completion);
    }
    void (^handler)(NSData *, NSURLResponse *, NSError *) =
        ^(NSData *d, NSURLResponse *r, NSError *e) {
            NSData *patched = VLCPatchJSON(d);
            VLCSaveDump(d, request.URL.path ?: @"");
            if (completion) completion(patched, r, e);
        };
    return %orig(request, handler);
}

- (NSURLSessionDataTask *)dataTaskWithURL:(NSURL *)url
                        completionHandler:(void (^)(NSData *, NSURLResponse *, NSError *))completion {
    NSString *host = url.host ?: @"";
    if (![host containsString:@"vidlist.pw"]) {
        return %orig(url, completion);
    }
    void (^handler)(NSData *, NSURLResponse *, NSError *) =
        ^(NSData *d, NSURLResponse *r, NSError *e) {
            NSData *patched = VLCPatchJSON(d);
            VLCSaveDump(d, url.path ?: @"");
            if (completion) completion(patched, r, e);
        };
    return %orig(url, handler);
}

%end

// Hook NSURLSessionConfiguration to inject our protocol into Alamofire sessions
// Alamofire creates its own session configs — registerClass alone won't catch them
// This forces VLCDumpProtocol into EVERY session's protocol stack
%hook NSURLSessionConfiguration

- (NSArray *)protocolClasses {
    NSMutableArray *classes = [NSMutableArray arrayWithArray:%orig ?: @[]];
    if (![classes containsObject:[VLCDumpProtocol class]]) {
        [classes insertObject:[VLCDumpProtocol class] atIndex:0];
    }
    return classes;
}

%end

// ─────────────────────────────────────────────────────────────────────────────
// Hook: NSUserDefaults – intercept any cached premium flags VidList writes
// ─────────────────────────────────────────────────────────────────────────────

static BOOL VLCIsPremiumKey(NSString *key) {
    if (!key) return NO;
    NSString *lower = [key lowercaseString];
    return [lower containsString:@"premium"]
        || [lower containsString:@"trial"]
        || [lower containsString:@"subscri"]
        || [lower containsString:@"isactive"];
}

%hook NSUserDefaults

- (id)objectForKey:(NSString *)key {
    if (VLCIsPremiumKey(key)) {
        // Return YES/true for any premium flag read
        id orig = %orig;
        if ([orig isKindOfClass:[NSNumber class]]) return @YES;
    }
    return %orig;
}

- (BOOL)boolForKey:(NSString *)key {
    if (VLCIsPremiumKey(key)) return YES;
    return %orig;
}

- (NSInteger)integerForKey:(NSString *)key {
    if (VLCIsPremiumKey(key)) return 1;
    return %orig;
}

%end

// ─────────────────────────────────────────────────────────────────────────────
// Hook: UIApplication – set up overlay once app is active
// ─────────────────────────────────────────────────────────────────────────────

%hook UIApplication

- (void)applicationDidBecomeActive:(UIApplication *)application {
    %orig;
    VLCSetupOverlay();
}

%end

// ─────────────────────────────────────────────────────────────────────────────
// Constructor
// ─────────────────────────────────────────────────────────────────────────────

%ctor {
    // Register NSURLProtocol interceptor — catches Alamofire delegate sessions
    [NSURLProtocol registerClass:[VLCDumpProtocol class]];

    // Warm cache
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0), ^{
        (void)[VLCrawler shared];
    });
    // Trigger overlay setup after a short delay (scenes not ready at inject time)
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        VLCSetupOverlay();
    });
}
