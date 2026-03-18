#import <UIKit/UIKit.h>
#import "VLCrawler.h"

// Forward declare results VC
@interface VLCrawlerResultsVC : UITableViewController
- (instancetype)initWithResults:(NSArray<VLVideoResult *> *)results title:(NSString *)title;
@end


// ─────────────────────────────────────────────
// VLDumpViewerVC — lists captured API responses
// with inline viewer + share sheet
// ─────────────────────────────────────────────

@interface VLDumpViewerVC : UITableViewController
@end

@implementation VLDumpViewerVC {
    NSMutableArray<NSString *> *_files; // full paths
}

+ (NSString *)dumpDir {
    NSString *docs = NSSearchPathForDirectoriesInDomains(
        NSDocumentDirectory, NSUserDomainMask, YES).firstObject;
    return [docs stringByAppendingPathComponent:@"VLDumps"];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"📡 API Dumps";
    self.navigationItem.rightBarButtonItem =
        [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemTrash
                                                      target:self
                                                      action:@selector(_clearAll)];
    [self.tableView registerClass:[UITableViewCell class] forCellReuseIdentifier:@"dump"];
    [self _reload];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self _reload];
}

- (void)_reload {
    _files = [NSMutableArray array];
    NSString *dir = [VLDumpViewerVC dumpDir];
    NSArray *all = [[NSFileManager defaultManager]
        contentsOfDirectoryAtPath:dir error:nil] ?: @[];
    // Sort newest first
    NSArray *sorted = [all sortedArrayUsingComparator:^NSComparisonResult(NSString *a, NSString *b) {
        return [b compare:a];
    }];
    for (NSString *f in sorted) {
        if ([f hasSuffix:@".json"]) {
            [_files addObject:[dir stringByAppendingPathComponent:f]];
        }
    }
    [self.tableView reloadData];
}

- (NSInteger)tableView:(UITableView *)tv numberOfRowsInSection:(NSInteger)s {
    return _files.count ?: 1;
}

- (NSString *)tableView:(UITableView *)tv titleForHeaderInSection:(NSInteger)s {
    return [NSString stringWithFormat:@"%lu dump%@ captured",
            (unsigned long)_files.count, _files.count == 1 ? @"" : @"s"];
}

- (UITableViewCell *)tableView:(UITableView *)tv
         cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tv dequeueReusableCellWithIdentifier:@"dump" forIndexPath:indexPath];
    if (!_files.count) {
        cell.textLabel.text       = @"No dumps yet — launch the app and log in";
        cell.textLabel.textColor  = [UIColor secondaryLabelColor];
        cell.textLabel.font       = [UIFont systemFontOfSize:13];
        cell.textLabel.numberOfLines = 0;
        cell.accessoryType        = UITableViewCellAccessoryNone;
        cell.selectionStyle       = UITableViewCellSelectionStyleNone;
        return cell;
    }
    NSString *full = _files[indexPath.row];
    NSString *name = full.lastPathComponent;
    // Size
    NSDictionary *attrs = [[NSFileManager defaultManager] attributesOfItemAtPath:full error:nil];
    long long size = [attrs[NSFileSize] longLongValue];
    cell.textLabel.text            = name;
    cell.textLabel.font            = [UIFont monospacedSystemFontOfSize:11 weight:UIFontWeightRegular];
    cell.textLabel.numberOfLines   = 2;
    cell.detailTextLabel.text      = [NSString stringWithFormat:@"%.1f KB", size / 1024.0];
    cell.accessoryType             = UITableViewCellAccessoryDisclosureIndicator;
    return cell;
}

- (void)tableView:(UITableView *)tv didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tv deselectRowAtIndexPath:indexPath animated:YES];
    if (!_files.count) return;

    NSString *full = _files[indexPath.row];
    NSData   *data = [NSData dataWithContentsOfFile:full];
    NSString *text = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] ?: @"(binary)";

    UIAlertController *ac = [UIAlertController
        alertControllerWithTitle:full.lastPathComponent
                         message:nil
                  preferredStyle:UIAlertControllerStyleActionSheet];

    [ac addAction:[UIAlertAction actionWithTitle:@"📋  Copy JSON"
                                           style:UIAlertActionStyleDefault
                                         handler:^(UIAlertAction *a) {
        [UIPasteboard generalPasteboard].string = text;
    }]];

    [ac addAction:[UIAlertAction actionWithTitle:@"📤  Share file"
                                           style:UIAlertActionStyleDefault
                                         handler:^(UIAlertAction *a) {
        NSURL *u = [NSURL fileURLWithPath:full];
        UIActivityViewController *share = [[UIActivityViewController alloc]
            initWithActivityItems:@[u] applicationActivities:nil];
        if (share.popoverPresentationController) {
            UITableViewCell *cell = [tv cellForRowAtIndexPath:indexPath];
            share.popoverPresentationController.sourceView = cell;
            share.popoverPresentationController.sourceRect = cell.bounds;
        }
        [self presentViewController:share animated:YES completion:nil];
    }]];

    [ac addAction:[UIAlertAction actionWithTitle:@"🗑  Delete"
                                           style:UIAlertActionStyleDestructive
                                         handler:^(UIAlertAction *a) {
        [[NSFileManager defaultManager] removeItemAtPath:full error:nil];
        [_files removeObjectAtIndex:indexPath.row];
        [tv deleteRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationAutomatic];
    }]];

    [ac addAction:[UIAlertAction actionWithTitle:@"Cancel"
                                           style:UIAlertActionStyleCancel handler:nil]];

    if (ac.popoverPresentationController) {
        UITableViewCell *cell = [tv cellForRowAtIndexPath:indexPath];
        ac.popoverPresentationController.sourceView = cell;
        ac.popoverPresentationController.sourceRect = cell.bounds;
    }
    [self presentViewController:ac animated:YES completion:nil];
}

- (UISwipeActionsConfiguration *)tableView:(UITableView *)tv
trailingSwipeActionsConfigurationForRowAtIndexPath:(NSIndexPath *)indexPath {
    if (!_files.count) return nil;
    UIContextualAction *del = [UIContextualAction
        contextualActionWithStyle:UIContextualActionStyleDestructive
                            title:@"Delete"
                          handler:^(UIContextualAction *a, UIView *src, void(^done)(BOOL)) {
        [[NSFileManager defaultManager] removeItemAtPath:_files[indexPath.row] error:nil];
        [_files removeObjectAtIndex:indexPath.row];
        [tv deleteRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationAutomatic];
        done(YES);
    }];
    return [UISwipeActionsConfiguration configurationWithActions:@[del]];
}

- (void)_clearAll {
    UIAlertController *ac = [UIAlertController
        alertControllerWithTitle:@"Clear all dumps?"
                         message:nil
                  preferredStyle:UIAlertControllerStyleAlert];
    [ac addAction:[UIAlertAction actionWithTitle:@"Clear"
                                           style:UIAlertActionStyleDestructive
                                         handler:^(UIAlertAction *a) {
        for (NSString *f in _files)
            [[NSFileManager defaultManager] removeItemAtPath:f error:nil];
        [_files removeAllObjects];
        [self.tableView reloadData];
    }]];
    [ac addAction:[UIAlertAction actionWithTitle:@"Cancel"
                                           style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:ac animated:YES completion:nil];
}

@end

// ─────────────────────────────────────────────
// VLCrawlerSettingsVC  –  list of crawled sites + "add new" 
// This is the root VC pushed by the tweak's injected button
// ─────────────────────────────────────────────

@interface VLCrawlerSettingsVC : UITableViewController
@end

@implementation VLCrawlerSettingsVC {
    NSMutableArray<NSDictionary *> *_savedJobs;   // [{url, depth, title}]
    VLCrawlJob                     *_activeJob;
    UIProgressView                 *_progressView;
    UILabel                        *_progressLabel;
    NSUInteger                      _foundCount;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"🔍 VL Crawler";

    // Load saved jobs from UserDefaults
    _savedJobs = [NSMutableArray array];
    NSArray *saved = [[NSUserDefaults standardUserDefaults] arrayForKey:@"VLCrawlerJobs"];
    if (saved) [_savedJobs addObjectsFromArray:saved];

    // Nav bar buttons
    self.navigationItem.rightBarButtonItem =
        [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemAdd
                                                      target:self
                                                      action:@selector(_addNewJob)];

    self.navigationItem.leftBarButtonItem =
        [[UIBarButtonItem alloc] initWithTitle:@"Done"
                                         style:UIBarButtonItemStyleDone
                                        target:self
                                        action:@selector(_dismiss)];

    // Progress header
    UIView *header = [[UIView alloc] initWithFrame:CGRectMake(0, 0, self.view.bounds.size.width, 60)];
    header.backgroundColor = [UIColor clearColor];

    _progressView = [[UIProgressView alloc] initWithProgressViewStyle:UIProgressViewStyleDefault];
    _progressView.frame = CGRectMake(16, 28, self.view.bounds.size.width - 32, 4);
    _progressView.alpha = 0;
    _progressView.tintColor = [UIColor systemBlueColor];

    _progressLabel = [[UILabel alloc] initWithFrame:CGRectMake(16, 8, self.view.bounds.size.width - 32, 18)];
    _progressLabel.font      = [UIFont systemFontOfSize:12];
    _progressLabel.textColor = [UIColor secondaryLabelColor];
    _progressLabel.alpha     = 0;

    [header addSubview:_progressView];
    [header addSubview:_progressLabel];
    self.tableView.tableHeaderView = header;

    [self.tableView registerClass:[UITableViewCell class] forCellReuseIdentifier:@"jobCell"];
}

- (void)_dismiss { [self dismissViewControllerAnimated:YES completion:nil]; }

// ─── Add new crawl job ────────────────────────

- (void)_addNewJob {
    UIAlertController *ac = [UIAlertController
        alertControllerWithTitle:@"Add Crawl Source"
                         message:@"Enter the URL to crawl for video links"
                  preferredStyle:UIAlertControllerStyleAlert];

    [ac addTextFieldWithConfigurationHandler:^(UITextField *tf) {
        tf.placeholder   = @"https://example.com/videos";
        tf.keyboardType  = UIKeyboardTypeURL;
        tf.autocorrectionType = UITextAutocorrectionTypeNo;
        tf.autocapitalizationType = UITextAutocapitalizationTypeNone;
    }];

    [ac addTextFieldWithConfigurationHandler:^(UITextField *tf) {
        tf.placeholder  = @"Max depth (1–5, default 2)";
        tf.keyboardType = UIKeyboardTypeNumberPad;
    }];

    [ac addTextFieldWithConfigurationHandler:^(UITextField *tf) {
        tf.placeholder = @"Label (optional)";
    }];

    [ac addAction:[UIAlertAction actionWithTitle:@"Crawl"
                                           style:UIAlertActionStyleDefault
                                         handler:^(UIAlertAction *a) {
        NSString *url   = ac.textFields[0].text;
        NSUInteger depth = [ac.textFields[1].text integerValue];
        NSString *label = ac.textFields[2].text;

        if (!url.length || ![[NSURL URLWithString:url] scheme]) {
            [self _showError:@"Invalid URL"];
            return;
        }
        if (depth < 1 || depth > 5) depth = 2;
        if (!label.length) label = [NSURL URLWithString:url].host ?: url;

        NSDictionary *job = @{@"url": url, @"depth": @(depth), @"label": label};
        [_savedJobs addObject:job];
        [[NSUserDefaults standardUserDefaults] setObject:[_savedJobs copy] forKey:@"VLCrawlerJobs"];

        NSIndexPath *ip = [NSIndexPath indexPathForRow:_savedJobs.count - 1 inSection:0];
        [self.tableView insertRowsAtIndexPaths:@[ip] withRowAnimation:UITableViewRowAnimationAutomatic];

        [self _startCrawlForJobDict:job atIndex:_savedJobs.count - 1];
    }]];

    [ac addAction:[UIAlertAction actionWithTitle:@"Cancel"
                                           style:UIAlertActionStyleCancel
                                         handler:nil]];
    [self presentViewController:ac animated:YES completion:nil];
}

// ─── Start crawl ─────────────────────────────

- (void)_startCrawlForJobDict:(NSDictionary *)jobDict atIndex:(NSInteger)idx {
    if (_activeJob && !_activeJob.isCancelled) {
        [self _showError:@"A crawl is already running. Cancel it first."];
        return;
    }

    NSString  *url   = jobDict[@"url"];
    NSUInteger depth = [jobDict[@"depth"] unsignedIntegerValue];
    NSString  *label = jobDict[@"label"];

    _activeJob   = [[VLCrawlJob alloc] initWithRootURL:url maxDepth:depth maxLinks:1000];
    _foundCount  = 0;

    [UIView animateWithDuration:0.2 animations:^{
        _progressView.alpha  = 1;
        _progressLabel.alpha = 1;
        _progressLabel.text  = [NSString stringWithFormat:@"Starting crawl: %@", label];
        _progressView.progress = 0;
    }];

    // Update nav bar to show cancel
    UIBarButtonItem *cancel = [[UIBarButtonItem alloc]
        initWithTitle:@"Cancel"
                style:UIBarButtonItemStylePlain
               target:self
               action:@selector(_cancelCrawl)];
    cancel.tintColor = [UIColor systemRedColor];
    self.navigationItem.rightBarButtonItem = cancel;

    __weak typeof(self) weak = self;
    [[VLCrawler shared] crawlJob:_activeJob
                        progress:^(NSString *currentURL, NSUInteger found) {
        __strong typeof(weak) s = weak;
        if (!s) return;
        s->_foundCount = found;
        s->_progressLabel.text = [NSString stringWithFormat:@"Found %lu  ·  %@",
                                  (unsigned long)found,
                                  [NSURL URLWithString:currentURL].path ?: currentURL];
        // Indeterminate look – pulse progress
        s->_progressView.progress = fmodf(s->_progressView.progress + 0.02f, 1.0f);
    }
                      completion:^(NSArray<NSDictionary *> *results, NSError *error) {
        __strong typeof(weak) s = weak;
        if (!s) return;

        [UIView animateWithDuration:0.3 animations:^{
            s->_progressView.alpha  = 0;
            s->_progressLabel.alpha = 0;
        }];

        // Restore add button
        s.navigationItem.rightBarButtonItem =
            [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemAdd
                                                          target:s action:@selector(_addNewJob)];

        NSArray<VLVideoResult *> *videoResults = (NSArray<VLVideoResult *> *)results;
        if (!videoResults.count) {
            [s _showError:[NSString stringWithFormat:@"No video links found on %@", label]];
            return;
        }

        // Reload the row to update count badge
        [s.tableView reloadRowsAtIndexPaths:@[[NSIndexPath indexPathForRow:idx inSection:0]]
                           withRowAnimation:UITableViewRowAnimationNone];

        // Push results
        VLCrawlerResultsVC *rvc = [[VLCrawlerResultsVC alloc] initWithResults:videoResults
                                                                         title:label];
        [s.navigationController pushViewController:rvc animated:YES];
    }];
}

- (void)_cancelCrawl {
    [_activeJob cancel];
    self.navigationItem.rightBarButtonItem =
        [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemAdd
                                                      target:self
                                                      action:@selector(_addNewJob)];
    [UIView animateWithDuration:0.2 animations:^{
        _progressView.alpha = 0; _progressLabel.alpha = 0;
    }];
}

// ─── Table ───────────────────────────────────

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tv {
    return 2;
}

- (NSInteger)tableView:(UITableView *)tv numberOfRowsInSection:(NSInteger)s {
    if (s == 1) return 1; // Dumps row
    return _savedJobs.count;
}

- (NSString *)tableView:(UITableView *)tv titleForHeaderInSection:(NSInteger)s {
    if (s == 1) return @"API Response Dumps";
    return _savedJobs.count ? @"Saved Sources" : nil;
}

- (NSString *)tableView:(UITableView *)tv titleForFooterInSection:(NSInteger)s {
    if (s == 1) {
        NSString *dir = [VLDumpViewerVC dumpDir];
        NSArray *files = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:dir error:nil];
        NSUInteger n = [[files filteredArrayUsingPredicate:
            [NSPredicate predicateWithFormat:@"self ENDSWITH '.json'"]] count];
        return [NSString stringWithFormat:@"%lu file%@ captured from vidlist.pw",
                (unsigned long)n, n == 1 ? @"" : @"s"];
    }
    return _savedJobs.count ? nil : @"Tap + to add a URL to crawl for video links.";
}

- (UITableViewCell *)tableView:(UITableView *)tv
         cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.section == 1) {
        UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1
                                                       reuseIdentifier:@"dumpNav"];
        NSString *dir = [VLDumpViewerVC dumpDir];
        NSArray *files = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:dir error:nil];
        NSUInteger n = [[files filteredArrayUsingPredicate:
            [NSPredicate predicateWithFormat:@"self ENDSWITH '.json'"]] count];
        cell.textLabel.text       = @"View Captured Responses";
        cell.detailTextLabel.text = n ? [NSString stringWithFormat:@"%lu", (unsigned long)n] : @"None yet";
        cell.accessoryType        = UITableViewCellAccessoryDisclosureIndicator;
        cell.imageView.image      = [UIImage systemImageNamed:@"doc.text.magnifyingglass"];
        return cell;
    }

    UITableViewCell *cell = [tv dequeueReusableCellWithIdentifier:@"jobCell"
                                                     forIndexPath:indexPath];
    NSDictionary *job = _savedJobs[indexPath.row];
    NSString *url = job[@"url"];
    NSUInteger cached = [[VLCrawler shared] cachedResultsForRootURL:url].count;

    cell.textLabel.text       = job[@"label"];
    cell.textLabel.font       = [UIFont systemFontOfSize:15 weight:UIFontWeightSemibold];
    cell.textLabel.numberOfLines = 1;

    cell.detailTextLabel.text = [NSString stringWithFormat:@"depth %@  ·  %lu cached  ·  %@",
                                 job[@"depth"], (unsigned long)cached, url];
    cell.detailTextLabel.font = [UIFont systemFontOfSize:11];
    cell.detailTextLabel.numberOfLines = 1;
    cell.detailTextLabel.lineBreakMode = NSLineBreakByTruncatingMiddle;
    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    return cell;
}

- (void)tableView:(UITableView *)tv didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tv deselectRowAtIndexPath:indexPath animated:YES];
    if (indexPath.section == 1) {
        VLDumpViewerVC *dvc = [[VLDumpViewerVC alloc] initWithStyle:UITableViewStyleInsetGrouped];
        [self.navigationController pushViewController:dvc animated:YES];
        return;
    }
    NSDictionary *job = _savedJobs[indexPath.row];

    NSArray<VLVideoResult *> *cached = [[VLCrawler shared] cachedResultsForRootURL:job[@"url"]];

    UIAlertController *ac = [UIAlertController alertControllerWithTitle:job[@"label"]
                                                                message:job[@"url"]
                                                         preferredStyle:UIAlertControllerStyleActionSheet];

    if (cached.count) {
        [ac addAction:[UIAlertAction actionWithTitle:[NSString stringWithFormat:@"📺  View %lu cached links", (unsigned long)cached.count]
                                               style:UIAlertActionStyleDefault
                                             handler:^(UIAlertAction *a) {
            VLCrawlerResultsVC *rvc = [[VLCrawlerResultsVC alloc] initWithResults:cached
                                                                             title:job[@"label"]];
            [self.navigationController pushViewController:rvc animated:YES];
        }]];
    }

    [ac addAction:[UIAlertAction actionWithTitle:@"🔄  Re-crawl"
                                           style:UIAlertActionStyleDefault
                                         handler:^(UIAlertAction *a) {
        [[VLCrawler shared] clearCacheForRootURL:job[@"url"]];
        [self _startCrawlForJobDict:job atIndex:indexPath.row];
    }]];

    [ac addAction:[UIAlertAction actionWithTitle:@"🗑  Clear cache"
                                           style:UIAlertActionStyleDestructive
                                         handler:^(UIAlertAction *a) {
        [[VLCrawler shared] clearCacheForRootURL:job[@"url"]];
        [tv reloadRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationNone];
    }]];

    [ac addAction:[UIAlertAction actionWithTitle:@"❌  Remove"
                                           style:UIAlertActionStyleDestructive
                                         handler:^(UIAlertAction *a) {
        [[VLCrawler shared] clearCacheForRootURL:job[@"url"]];
        [_savedJobs removeObjectAtIndex:indexPath.row];
        [[NSUserDefaults standardUserDefaults] setObject:[_savedJobs copy] forKey:@"VLCrawlerJobs"];
        [tv deleteRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationAutomatic];
    }]];

    [ac addAction:[UIAlertAction actionWithTitle:@"Cancel"
                                           style:UIAlertActionStyleCancel
                                         handler:nil]];

    if (ac.popoverPresentationController) {
        UITableViewCell *cell = [tv cellForRowAtIndexPath:indexPath];
        ac.popoverPresentationController.sourceView = cell;
        ac.popoverPresentationController.sourceRect = cell.bounds;
    }
    [self presentViewController:ac animated:YES completion:nil];
}

- (UISwipeActionsConfiguration *)tableView:(UITableView *)tv
trailingSwipeActionsConfigurationForRowAtIndexPath:(NSIndexPath *)indexPath {
    UIContextualAction *del = [UIContextualAction
        contextualActionWithStyle:UIContextualActionStyleDestructive
                            title:@"Remove"
                          handler:^(UIContextualAction *a, UIView *src, void(^done)(BOOL)) {
        NSDictionary *job = _savedJobs[indexPath.row];
        [[VLCrawler shared] clearCacheForRootURL:job[@"url"]];
        [_savedJobs removeObjectAtIndex:indexPath.row];
        [[NSUserDefaults standardUserDefaults] setObject:[_savedJobs copy] forKey:@"VLCrawlerJobs"];
        [tv deleteRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationAutomatic];
        done(YES);
    }];
    return [UISwipeActionsConfiguration configurationWithActions:@[del]];
}

// ─── Error helper ─────────────────────────────

- (void)_showError:(NSString *)msg {
    UIAlertController *ac = [UIAlertController alertControllerWithTitle:@"VL Crawler"
                                                                message:msg
                                                         preferredStyle:UIAlertControllerStyleAlert];
    [ac addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:ac animated:YES completion:nil];
}

@end
