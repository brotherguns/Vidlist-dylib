#import "VLCrawler.h"
#import <UIKit/UIKit.h>

// ─────────────────────────────────────────────
#pragma mark - VLVideoResult
// ─────────────────────────────────────────────

@implementation VLVideoResult

+ (BOOL)supportsSecureCoding { return YES; }

- (instancetype)initWithCoder:(NSCoder *)coder {
    self = [super init];
    if (self) {
        _videoURL  = [coder decodeObjectOfClass:[NSString class] forKey:@"videoURL"];
        _pageURL   = [coder decodeObjectOfClass:[NSString class] forKey:@"pageURL"];
        _title     = [coder decodeObjectOfClass:[NSString class] forKey:@"title"];
        _mimeHint  = [coder decodeObjectOfClass:[NSString class] forKey:@"mimeHint"];
        _cachedAt  = [coder decodeObjectOfClass:[NSDate   class] forKey:@"cachedAt"];
    }
    return self;
}

- (void)encodeWithCoder:(NSCoder *)coder {
    [coder encodeObject:_videoURL forKey:@"videoURL"];
    [coder encodeObject:_pageURL  forKey:@"pageURL"];
    [coder encodeObject:_title    forKey:@"title"];
    [coder encodeObject:_mimeHint forKey:@"mimeHint"];
    [coder encodeObject:_cachedAt forKey:@"cachedAt"];
}

- (NSString *)description {
    return [NSString stringWithFormat:@"<VLVideoResult %@ [%@]>", _title, _mimeHint];
}

@end

// ─────────────────────────────────────────────
#pragma mark - VLCrawlJob
// ─────────────────────────────────────────────

@implementation VLCrawlJob {
    BOOL _cancelled;
}

- (instancetype)initWithRootURL:(NSString *)url maxDepth:(NSUInteger)depth maxLinks:(NSUInteger)cap {
    self = [super init];
    if (self) {
        _rootURL  = [url copy];
        _maxDepth = depth;
        _maxLinks = cap > 0 ? cap : 500;
    }
    return self;
}

- (void)cancel { _cancelled = YES; }
- (BOOL)isCancelled { return _cancelled; }

@end

// ─────────────────────────────────────────────
#pragma mark - VLCrawler (private interface)
// ─────────────────────────────────────────────

// Extensions that are considered video
static NSArray<NSString *> *VideoExtensions(void) {
    static NSArray *exts;
    static dispatch_once_t t;
    dispatch_once(&t, ^{
        exts = @[@"mp4", @"m3u8", @"m3u", @"webm", @"mkv", @"avi",
                 @"mov", @"flv", @"ts", @"mpd", @"ogg", @"ogv",
                 @"mp2t", @"m4v", @"3gp"];
    });
    return exts;
}

// Keywords that strongly suggest a video URL even without a known extension
static NSArray<NSString *> *VideoKeywords(void) {
    static NSArray *kw;
    static dispatch_once_t t;
    dispatch_once(&t, ^{
        kw = @[@"stream", @"video", @"media", @"hls", @"dash",
               @"playlist", @"manifest", @"embed", @"player"];
    });
    return kw;
}

@interface VLCrawler ()
@property (nonatomic, strong) NSURLSession         *session;
@property (nonatomic, strong) NSMutableArray       *cache;       // [VLVideoResult]
@property (nonatomic, strong) dispatch_queue_t      crawlQueue;
@property (nonatomic, strong) NSLock               *cacheLock;
@end

@implementation VLCrawler

+ (instancetype)shared {
    static VLCrawler *s;
    static dispatch_once_t t;
    dispatch_once(&t, ^{ s = [[VLCrawler alloc] init]; });
    return s;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        NSURLSessionConfiguration *cfg = [NSURLSessionConfiguration defaultSessionConfiguration];
        cfg.timeoutIntervalForRequest  = 15;
        cfg.timeoutIntervalForResource = 30;
        cfg.HTTPAdditionalHeaders = @{
            @"User-Agent": @"Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) "
                           @"AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile/15E148"
        };
        _session    = [NSURLSession sessionWithConfiguration:cfg];
        _crawlQueue = dispatch_queue_create("com.brotherguns.vlcrawler.crawl",
                                            DISPATCH_QUEUE_CONCURRENT);
        _cacheLock  = [[NSLock alloc] init];
        _cache      = [NSMutableArray array];
        [self loadCacheFromDisk];
    }
    return self;
}

// ─────────────────────────────────────────────
#pragma mark - Public crawl entry
// ─────────────────────────────────────────────

- (void)crawlJob:(VLCrawlJob *)job
        progress:(nullable VLCrawlerProgressBlock)progress
      completion:(VLCrawlerCompletionBlock)completion {

    dispatch_async(_crawlQueue, ^{
        NSMutableSet    *visited    = [NSMutableSet set];
        NSMutableSet    *videosSeen = [NSMutableSet set];
        NSMutableArray  *results    = [NSMutableArray array];
        dispatch_semaphore_t sem    = dispatch_semaphore_create(8); // 8 concurrent fetches

        [self _crawlURL:job.rootURL
               rootHost:[self _hostFromURL:job.rootURL]
                  depth:0
                    job:job
                visited:visited
             videosSeen:videosSeen
                results:results
               progress:progress
                    sem:sem];

        // Merge new results into cache
        [self _mergeResults:results forRootURL:job.rootURL];
        [self saveCacheToDisk];

        dispatch_async(dispatch_get_main_queue(), ^{
            completion(results, nil);
        });
    });
}

// ─────────────────────────────────────────────
#pragma mark - Recursive worker
// ─────────────────────────────────────────────

- (void)_crawlURL:(NSString *)urlStr
         rootHost:(NSString *)rootHost
            depth:(NSUInteger)depth
              job:(VLCrawlJob *)job
          visited:(NSMutableSet *)visited
       videosSeen:(NSMutableSet *)videosSeen
          results:(NSMutableArray *)results
         progress:(nullable VLCrawlerProgressBlock)progress
               sem:(dispatch_semaphore_t)sem {

    if (job.isCancelled)               return;
    if (depth > job.maxDepth)          return;
    if (results.count >= job.maxLinks) return;
    if (!urlStr.length)                return;

    @synchronized(visited) {
        if ([visited containsObject:urlStr]) return;
        [visited addObject:urlStr];
    }

    if (progress) {
        dispatch_async(dispatch_get_main_queue(), ^{
            progress(urlStr, results.count);
        });
    }

    dispatch_semaphore_wait(sem, DISPATCH_TIME_FOREVER);

    NSURL *url = [NSURL URLWithString:urlStr];
    if (!url) { dispatch_semaphore_signal(sem); return; }

    // Check if this URL itself looks like a direct video link before fetching
    if ([self _isVideoURL:urlStr]) {
        dispatch_semaphore_signal(sem);
        [self _addVideoURL:urlStr pageURL:urlStr title:nil results:results videosSeen:videosSeen];
        return;
    }

    __block NSData   *data = nil;
    __block NSURLResponse *resp = nil;
    __block NSError  *err  = nil;

    dispatch_semaphore_t fetchSem = dispatch_semaphore_create(0);
    NSURLSessionDataTask *task = [_session dataTaskWithURL:url
                                         completionHandler:^(NSData *d, NSURLResponse *r, NSError *e) {
        data = d; resp = r; err = e;
        dispatch_semaphore_signal(fetchSem);
    }];
    [task resume];
    dispatch_semaphore_wait(fetchSem, dispatch_time(DISPATCH_TIME_NOW, 20 * NSEC_PER_SEC));
    dispatch_semaphore_signal(sem);

    if (err || !data) return;

    NSString *contentType = @"";
    if ([resp isKindOfClass:[NSHTTPURLResponse class]]) {
        contentType = [((NSHTTPURLResponse *)resp).allHeaderFields[@"Content-Type"] lowercaseString] ?: @"";
    }

    // Binary video content – direct link
    if ([self _contentTypeIsVideo:contentType]) {
        [self _addVideoURL:urlStr pageURL:urlStr title:nil results:results videosSeen:videosSeen];
        return;
    }

    // Parse as text (HTML / m3u8 / mpd)
    NSString *body = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding]
                  ?: [[NSString alloc] initWithData:data encoding:NSISOLatin1StringEncoding];
    if (!body) return;

    NSString *pageTitle = [self _extractTitle:body] ?: [url lastPathComponent] ?: urlStr;

    // Extract video sources first
    NSArray<NSString *> *videoLinks = [self _extractVideoLinks:body baseURL:urlStr];
    for (NSString *vl in videoLinks) {
        if (results.count >= job.maxLinks) break;
        [self _addVideoURL:vl pageURL:urlStr title:pageTitle results:results videosSeen:videosSeen];
    }

    if (job.isCancelled || results.count >= job.maxLinks) return;
    if (depth >= job.maxDepth) return;

    // Extract navigable links on the same host
    NSArray<NSString *> *pageLinks = [self _extractPageLinks:body baseURL:urlStr rootHost:rootHost];

    // Recurse in parallel (bounded by semaphore)
    dispatch_group_t group = dispatch_group_create();
    for (NSString *link in pageLinks) {
        if (job.isCancelled || results.count >= job.maxLinks) break;
        dispatch_group_async(group, _crawlQueue, ^{
            [self _crawlURL:link
                   rootHost:rootHost
                      depth:depth + 1
                        job:job
                    visited:visited
                 videosSeen:videosSeen
                    results:results
                   progress:progress
                        sem:sem];
        });
    }
    dispatch_group_wait(group, DISPATCH_TIME_FOREVER);
}

// ─────────────────────────────────────────────
#pragma mark - Parsing helpers
// ─────────────────────────────────────────────

- (void)_addVideoURL:(NSString *)videoURL
             pageURL:(NSString *)pageURL
               title:(nullable NSString *)title
             results:(NSMutableArray *)results
          videosSeen:(NSMutableSet *)videosSeen {

    NSString *canonical = [videoURL lowercaseString];
    @synchronized(videosSeen) {
        if ([videosSeen containsObject:canonical]) return;
        [videosSeen addObject:canonical];
    }

    VLVideoResult *r = [[VLVideoResult alloc] init];
    r.videoURL  = videoURL;
    r.pageURL   = pageURL;
    r.title     = title ?: [NSURL URLWithString:videoURL].lastPathComponent ?: videoURL;
    r.mimeHint  = [self _mimeHintForURL:videoURL];
    r.cachedAt  = [NSDate date];

    @synchronized(results) { [results addObject:r]; }
}

// Extract <title> from HTML
- (nullable NSString *)_extractTitle:(NSString *)html {
    NSRegularExpression *rx = [NSRegularExpression
        regularExpressionWithPattern:@"<title[^>]*>\\s*([^<]{1,120})\\s*</title>"
                             options:NSRegularExpressionCaseInsensitive error:nil];
    NSTextCheckingResult *m = [rx firstMatchInString:html options:0
                                               range:NSMakeRange(0, html.length)];
    if (!m || m.numberOfRanges < 2) return nil;
    NSRange r = [m rangeAtIndex:1];
    return r.location == NSNotFound ? nil : [html substringWithRange:r];
}

// Find direct video file/stream links in HTML source
- (NSArray<NSString *> *)_extractVideoLinks:(NSString *)body baseURL:(NSString *)base {
    NSMutableArray *found = [NSMutableArray array];
    NSMutableSet   *seen  = [NSMutableSet set];

    // Extensions to skip (definitely not video)
    NSArray *skipExts = @[@".png",@".jpg",@".jpeg",@".gif",@".svg",@".webp",
                          @".ico",@".css",@".js",@".woff",@".woff2",@".ttf",@".eot"];

    // Helper block — add a URL, optionally requiring _isVideoURL
    void (^tryAdd)(NSString *, BOOL) = ^(NSString *raw, BOOL requireVideoExt) {
        NSString *abs = [self _absoluteURL:raw base:base];
        if (!abs) return;
        NSString *lower = abs.lowercaseString;
        if ([seen containsObject:lower]) return;
        // Strip query for extension checks
        NSString *pathOnly = lower;
        NSRange q = [lower rangeOfString:@"?"];
        if (q.location != NSNotFound) pathOnly = [lower substringToIndex:q.location];
        // Reject known non-video extensions
        for (NSString *sk in skipExts) {
            if ([pathOnly hasSuffix:sk]) return;
        }
        if (requireVideoExt && ![self _isVideoURL:abs]) return;
        // Must at least be http(s)
        if (![abs hasPrefix:@"http"]) return;
        [seen addObject:lower];
        [found addObject:abs];
    };

    // ── 1. HTML attr with explicit video extension (strict) ─────────────────
    NSString *attrExtPat = [NSString stringWithFormat:
        @"(?:src|href|file|url|stream|source|path|data-src|data-url|data-file)"
        @"\\s*[=:]\\s*[\"']([^\"'\\s]{5,600}\\.(?:%@)[^\"'\\s]{0,60})[\"']",
        [VideoExtensions() componentsJoinedByString:@"|"]];

    // ── 2. Bare .m3u8 / .mpd / .ts in any quoted string (strict) ───────────
    NSString *bareHLSPat =
        @"[\"']([^\"'\\s]{8,600}\\.(?:m3u8|mpd|ts)(?:[?#][^\"'\\s]{0,100})?)[\"']";

    // ── 3. JSON key → video concept, absolute http URL (trusted) ────────────
    NSString *jsonKeyPat =
        @"\"(?:src|url|file|stream|source|hls|dash|manifest|video|videoUrl|fileUrl|"
        @"streamUrl|hlsUrl|mp4|mp4Url|mediaUrl|contentUrl|playbackUrl|videoSrc)\""
        @"\\s*:\\s*\"(https?://[^\"\\s]{8,600})\"";

    // ── 4. <source src="..."> tag (trusted — element guarantees video) ───────
    NSString *sourceTagPat =
        @"<source[^>]+src=[\"'](https?://[^\"'\\s]{8,500})[\"']";

    // ── 5. JS variable / object key assignments (trusted) ───────────────────
    //    Catches: file: "https://...",  src: "https://...",  hls: "https://..."
    //    and var src = "https://..."   (JWPlayer, VideoJS, hls.js, etc.)
    NSString *jsVarPat =
        @"(?:^|[{,;\\s])(?:file|src|source|hls|stream|url|video|mp4)"
        @"\\s*[=:]\\s*[\"'](https?://[^\"'\\s]{8,500})[\"']";

    // strict = URL must pass _isVideoURL; NO = trusted (any http URL)
    NSDictionary<NSString *, NSNumber *> *patterns = @{
        attrExtPat:  @YES,
        bareHLSPat:  @YES,
        jsonKeyPat:  @NO,
        sourceTagPat:@NO,
        jsVarPat:    @NO,
    };

    for (NSString *pat in patterns) {
        BOOL strict = [patterns[pat] boolValue];
        NSError *err = nil;
        NSRegularExpression *rx = [NSRegularExpression
            regularExpressionWithPattern:pat
                                 options:NSRegularExpressionCaseInsensitive
                                         |NSRegularExpressionAnchorsMatchLines
                                   error:&err];
        if (!rx) continue;
        [rx enumerateMatchesInString:body options:0 range:NSMakeRange(0, body.length)
                          usingBlock:^(NSTextCheckingResult *match, NSMatchingFlags flags, BOOL *stop) {
            if (match.numberOfRanges < 2) return;
            NSRange r = [match rangeAtIndex:1];
            if (r.location == NSNotFound) return;
            tryAdd([body substringWithRange:r], strict);
        }];
    }
    return found;
}

// Collect same-host page links for recursion
- (NSArray<NSString *> *)_extractPageLinks:(NSString *)body
                                    baseURL:(NSString *)base
                                   rootHost:(NSString *)rootHost {
    NSMutableArray *links = [NSMutableArray array];
    NSMutableSet   *seen  = [NSMutableSet set];

    NSString *pat = @"href=[\"']([^\"'#?]{3,300})[\"']";
    NSRegularExpression *rx = [NSRegularExpression
        regularExpressionWithPattern:pat options:NSRegularExpressionCaseInsensitive error:nil];
    [rx enumerateMatchesInString:body options:0 range:NSMakeRange(0, body.length)
                      usingBlock:^(NSTextCheckingResult *match, NSMatchingFlags flags, BOOL *stop) {
        if (match.numberOfRanges < 2) return;
        NSRange r = [match rangeAtIndex:1];
        if (r.location == NSNotFound) return;
        NSString *raw = [body substringWithRange:r];
        NSString *abs = [self _absoluteURL:raw base:base];
        if (!abs) return;
        NSString *host = [self _hostFromURL:abs];
        if (![host hasSuffix:rootHost] && ![rootHost hasSuffix:host]) return;
        if ([seen containsObject:abs]) return;
        if ([self _isVideoURL:abs]) return; // handled by video extractor
        // Skip non-HTML likely resources
        NSString *lower = abs.lowercaseString;
        for (NSString *skip in @[@".css",@".js",@".png",@".jpg",@".gif",@".svg",@".ico",@".woff",@".ttf"]) {
            if ([lower hasSuffix:skip]) return;
        }
        [seen addObject:abs];
        [links addObject:abs];
    }];
    return links;
}

// ─────────────────────────────────────────────
#pragma mark - URL helpers
// ─────────────────────────────────────────────

- (BOOL)_isVideoURL:(NSString *)urlStr {
    NSString *lower = [urlStr lowercaseString];
    // Strip query for extension check
    NSString *path = lower;
    NSRange q = [lower rangeOfString:@"?"];
    if (q.location != NSNotFound) path = [lower substringToIndex:q.location];
    NSString *ext = [path pathExtension];
    // Known video extension — always a hit
    if ([VideoExtensions() containsObject:ext]) return YES;
    // Explicit HLS/DASH markers anywhere in URL (even in query params)
    if ([lower containsString:@".m3u8"] || [lower containsString:@".mpd"] ||
        [lower containsString:@"hls/"] || [lower containsString:@"/manifest"]) return YES;
    return NO;
}

- (BOOL)_contentTypeIsVideo:(NSString *)ct {
    NSArray *videoTypes = @[@"video/", @"audio/", @"application/x-mpegurl",
                            @"application/vnd.apple.mpegurl", @"application/dash+xml",
                            @"application/octet-stream"]; // octet-stream is ambiguous but worth checking
    for (NSString *t in videoTypes) {
        if ([ct hasPrefix:t]) return YES;
    }
    return NO;
}

- (nullable NSString *)_absoluteURL:(NSString *)raw base:(NSString *)base {
    if (!raw.length) return nil;
    // Already absolute
    if ([raw hasPrefix:@"http://"] || [raw hasPrefix:@"https://"]) return raw;
    // Protocol-relative
    if ([raw hasPrefix:@"//"]) {
        NSURL *b = [NSURL URLWithString:base];
        return [NSString stringWithFormat:@"%@:%@", b.scheme, raw];
    }
    NSURL *b = [NSURL URLWithString:base];
    if (!b) return nil;
    NSURL *resolved = [NSURL URLWithString:raw relativeToURL:b];
    return resolved.absoluteString;
}

- (NSString *)_hostFromURL:(NSString *)urlStr {
    NSURL *u = [NSURL URLWithString:urlStr];
    NSString *host = u.host ?: @"";
    // Strip www. prefix for comparison
    if ([host hasPrefix:@"www."]) host = [host substringFromIndex:4];
    return host;
}

- (NSString *)_mimeHintForURL:(NSString *)urlStr {
    NSString *lower = [urlStr lowercaseString];
    NSString *path  = lower;
    NSRange q = [lower rangeOfString:@"?"];
    if (q.location != NSNotFound) path = [lower substringToIndex:q.location];
    NSString *ext = [path pathExtension];
    if (ext.length) return ext;
    if ([lower containsString:@"m3u8"] || [lower containsString:@"hls"]) return @"m3u8";
    if ([lower containsString:@"dash"] || [lower containsString:@"mpd"]) return @"mpd";
    return @"video";
}

// ─────────────────────────────────────────────
#pragma mark - Cache
// ─────────────────────────────────────────────

- (void)_mergeResults:(NSArray<VLVideoResult *> *)results forRootURL:(NSString *)rootURL {
    [_cacheLock lock];
    // Remove old entries for same root
    [_cache filterUsingPredicate:
        [NSPredicate predicateWithBlock:^BOOL(VLVideoResult *r, id _) {
            return ![r.pageURL hasPrefix:[self _baseOf:rootURL]];
        }]];
    [_cache addObjectsFromArray:results];
    [_cacheLock unlock];
}

- (NSString *)_baseOf:(NSString *)url {
    NSURL *u = [NSURL URLWithString:url];
    NSString *scheme = u.scheme ?: @"https";
    NSString *host   = u.host   ?: url;
    return [NSString stringWithFormat:@"%@://%@", scheme, host];
}

- (NSArray<VLVideoResult *> *)allCachedResults {
    [_cacheLock lock];
    NSArray *copy = [_cache copy];
    [_cacheLock unlock];
    return copy;
}

- (NSArray<VLVideoResult *> *)cachedResultsForRootURL:(NSString *)url {
    NSString *base = [self _baseOf:url];
    [_cacheLock lock];
    NSArray *copy = [_cache filteredArrayUsingPredicate:
        [NSPredicate predicateWithBlock:^BOOL(VLVideoResult *r, id _) {
            return [r.pageURL hasPrefix:base];
        }]];
    [_cacheLock unlock];
    return copy;
}

- (void)clearCacheForRootURL:(NSString *)url {
    NSString *base = [self _baseOf:url];
    [_cacheLock lock];
    [_cache filterUsingPredicate:
        [NSPredicate predicateWithBlock:^BOOL(VLVideoResult *r, id _) {
            return ![r.pageURL hasPrefix:base];
        }]];
    [_cacheLock unlock];
    [self saveCacheToDisk];
}

- (void)clearAllCache {
    [_cacheLock lock];
    [_cache removeAllObjects];
    [_cacheLock unlock];
    [self saveCacheToDisk];
}

+ (NSString *)cachePath {
    NSString *docs = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject;
    return [docs stringByAppendingPathComponent:@"VLCrawler_cache.archive"];
}

- (void)saveCacheToDisk {
    [_cacheLock lock];
    NSArray *snapshot = [_cache copy];
    [_cacheLock unlock];
    NSError *err = nil;
    NSData *data = [NSKeyedArchiver archivedDataWithRootObject:snapshot
                                        requiringSecureCoding:YES
                                                        error:&err];
    if (data) [data writeToFile:[VLCrawler cachePath] atomically:YES];
}

- (void)loadCacheFromDisk {
    NSData *data = [NSData dataWithContentsOfFile:[VLCrawler cachePath]];
    if (!data) return;
    NSError *err = nil;
    NSArray *loaded = [NSKeyedUnarchiver unarchivedArrayOfObjectsOfClass:[VLVideoResult class]
                                                                fromData:data
                                                                   error:&err];
    if (loaded) {
        [_cacheLock lock];
        [_cache addObjectsFromArray:loaded];
        [_cacheLock unlock];
    }
}

@end
