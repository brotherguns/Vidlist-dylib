#import <UIKit/UIKit.h>
#import <AVKit/AVKit.h>
#import "VLCrawler.h"

// ─────────────────────────────────────────────
// VLCrawlerResultsVC  –  table of found video links
// ─────────────────────────────────────────────

@interface VLCrawlerResultsVC : UITableViewController
- (instancetype)initWithResults:(NSArray<VLVideoResult *> *)results
                          title:(NSString *)title;
@end

@implementation VLCrawlerResultsVC {
    NSArray<VLVideoResult *> *_results;
    UIActivityIndicatorView  *_spinner;
}

- (instancetype)initWithResults:(NSArray<VLVideoResult *> *)results title:(NSString *)title {
    self = [super initWithStyle:UITableViewStyleInsetGrouped];
    if (self) {
        _results    = results;
        self.title  = title ?: @"Found Videos";
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];

    self.navigationItem.rightBarButtonItem =
        [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemAction
                                                      target:self
                                                      action:@selector(_export)];

    self.tableView.rowHeight = UITableViewAutomaticDimension;
    self.tableView.estimatedRowHeight = 64;
    [self.tableView registerClass:[UITableViewCell class] forCellReuseIdentifier:@"cell"];
}

// ─── UITableViewDataSource ───────────────────

- (NSInteger)tableView:(UITableView *)tv numberOfRowsInSection:(NSInteger)section {
    return _results.count;
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tv {
    return 1;
}

- (NSString *)tableView:(UITableView *)tv titleForHeaderInSection:(NSInteger)section {
    return [NSString stringWithFormat:@"%lu link%@ found",
            (unsigned long)_results.count, _results.count == 1 ? @"" : @"s"];
}

- (UITableViewCell *)tableView:(UITableView *)tv
         cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tv dequeueReusableCellWithIdentifier:@"cell" forIndexPath:indexPath];
    VLVideoResult *r = _results[indexPath.row];

    cell.textLabel.text          = r.title ?: r.videoURL;
    cell.textLabel.numberOfLines = 2;
    cell.textLabel.font          = [UIFont systemFontOfSize:14 weight:UIFontWeightMedium];

    cell.detailTextLabel.text    = r.videoURL;
    cell.detailTextLabel.font    = [UIFont monospacedSystemFontOfSize:10 weight:UIFontWeightRegular];
    cell.detailTextLabel.numberOfLines = 1;
    cell.detailTextLabel.lineBreakMode = NSLineBreakByTruncatingMiddle;

    // Badge for type
    UILabel *badge         = [[UILabel alloc] init];
    badge.text             = [r.mimeHint uppercaseString];
    badge.font             = [UIFont systemFontOfSize:10 weight:UIFontWeightBold];
    badge.textColor        = [UIColor whiteColor];
    badge.backgroundColor  = [self _colorForMime:r.mimeHint];
    badge.layer.cornerRadius = 4;
    badge.layer.masksToBounds = YES;
    badge.textAlignment    = NSTextAlignmentCenter;
    badge.frame            = CGRectMake(0, 0, 44, 20);
    cell.accessoryView     = badge;

    cell.textLabel.textColor       = [UIColor labelColor];
    cell.detailTextLabel.textColor = [UIColor secondaryLabelColor];
    cell.selectionStyle            = UITableViewCellSelectionStyleDefault;
    return cell;
}

- (UIColor *)_colorForMime:(NSString *)mime {
    if ([mime isEqualToString:@"m3u8"] || [mime isEqualToString:@"m3u"]) return [UIColor systemBlueColor];
    if ([mime isEqualToString:@"mpd"])   return [UIColor systemPurpleColor];
    if ([mime isEqualToString:@"mp4"] || [mime isEqualToString:@"m4v"]) return [UIColor systemGreenColor];
    return [UIColor systemOrangeColor];
}

// ─── UITableViewDelegate ─────────────────────

- (void)tableView:(UITableView *)tv didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tv deselectRowAtIndexPath:indexPath animated:YES];
    VLVideoResult *r = _results[indexPath.row];

    UIAlertController *ac = [UIAlertController alertControllerWithTitle:r.title
                                                                message:r.videoURL
                                                         preferredStyle:UIAlertControllerStyleActionSheet];

    [ac addAction:[UIAlertAction actionWithTitle:@"▶  Play"
                                           style:UIAlertActionStyleDefault
                                         handler:^(UIAlertAction *a) {
        [self _playURL:r.videoURL];
    }]];

    [ac addAction:[UIAlertAction actionWithTitle:@"📋  Copy link"
                                           style:UIAlertActionStyleDefault
                                         handler:^(UIAlertAction *a) {
        [UIPasteboard generalPasteboard].string = r.videoURL;
    }]];

    [ac addAction:[UIAlertAction actionWithTitle:@"🌐  Open in Safari"
                                           style:UIAlertActionStyleDefault
                                         handler:^(UIAlertAction *a) {
        NSURL *u = [NSURL URLWithString:r.videoURL];
        if (u) [[UIApplication sharedApplication] openURL:u options:@{} completionHandler:nil];
    }]];

    [ac addAction:[UIAlertAction actionWithTitle:@"Cancel"
                                           style:UIAlertActionStyleCancel
                                         handler:nil]];

    // iPad popover
    if (ac.popoverPresentationController) {
        UITableViewCell *cell = [tv cellForRowAtIndexPath:indexPath];
        ac.popoverPresentationController.sourceView = cell;
        ac.popoverPresentationController.sourceRect = cell.bounds;
    }
    [self presentViewController:ac animated:YES completion:nil];
}

- (UIContextMenuConfiguration *)tableView:(UITableView *)tv
contextMenuConfigurationForRowAtIndexPath:(NSIndexPath *)indexPath
                                    point:(CGPoint)point API_AVAILABLE(ios(13.0)) {
    VLVideoResult *r = _results[indexPath.row];
    return [UIContextMenuConfiguration configurationWithIdentifier:nil
                                                   previewProvider:nil
                                                    actionProvider:^UIMenu *(NSArray *suggested) {
        UIAction *play = [UIAction actionWithTitle:@"Play"
                                             image:[UIImage systemImageNamed:@"play.fill"]
                                        identifier:nil
                                           handler:^(__kindof UIAction *a) {
            [self _playURL:r.videoURL];
        }];
        UIAction *copy = [UIAction actionWithTitle:@"Copy Link"
                                             image:[UIImage systemImageNamed:@"link"]
                                        identifier:nil
                                           handler:^(__kindof UIAction *a) {
            [UIPasteboard generalPasteboard].string = r.videoURL;
        }];
        return [UIMenu menuWithTitle:r.title ?: @"" children:@[play, copy]];
    }];
}

// ─── Playback ────────────────────────────────

- (void)_playURL:(NSString *)urlStr {
    NSURL *url = [NSURL URLWithString:urlStr];
    if (!url) return;

    AVPlayerViewController *vc = [[AVPlayerViewController alloc] init];
    vc.player = [AVPlayer playerWithURL:url];
    [self presentViewController:vc animated:YES completion:^{
        [vc.player play];
    }];
}

// ─── Export ──────────────────────────────────

- (void)_export {
    NSMutableString *text = [NSMutableString string];
    for (VLVideoResult *r in _results) {
        [text appendFormat:@"%@\n%@\n\n", r.title ?: @"Untitled", r.videoURL];
    }
    NSData *data = [text dataUsingEncoding:NSUTF8StringEncoding];
    NSURL *tmp = [[NSURL fileURLWithPath:NSTemporaryDirectory()]
                    URLByAppendingPathComponent:@"vlcrawler_results.txt"];
    [data writeToURL:tmp atomically:YES];
    UIActivityViewController *share = [[UIActivityViewController alloc]
        initWithActivityItems:@[tmp] applicationActivities:nil];
    if (share.popoverPresentationController) {
        share.popoverPresentationController.barButtonItem = self.navigationItem.rightBarButtonItem;
    }
    [self presentViewController:share animated:YES completion:nil];
}

@end
