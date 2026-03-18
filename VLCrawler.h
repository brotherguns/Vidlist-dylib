#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef void (^VLCrawlerProgressBlock)(NSString *currentURL, NSUInteger found);
typedef void (^VLCrawlerCompletionBlock)(NSArray<NSDictionary *> *results, NSError * _Nullable error);

// A single cached video result
@interface VLVideoResult : NSObject <NSCoding, NSSecureCoding>
@property (nonatomic, strong) NSString *videoURL;
@property (nonatomic, strong) NSString *pageURL;      // page it was found on
@property (nonatomic, strong) NSString *title;         // page title or filename
@property (nonatomic, strong) NSString *mimeHint;      // mp4 / m3u8 / webm etc
@property (nonatomic, strong) NSDate   *cachedAt;
@end

// Manages a crawl job
@interface VLCrawlJob : NSObject
@property (nonatomic, readonly) NSString *rootURL;
@property (nonatomic, readonly) NSUInteger maxDepth;
@property (nonatomic, readonly) NSUInteger maxLinks;   // safety cap
@property (nonatomic, readonly, getter=isCancelled) BOOL cancelled;
- (instancetype)initWithRootURL:(NSString *)url maxDepth:(NSUInteger)depth maxLinks:(NSUInteger)cap;
- (void)cancel;
@end

@interface VLCrawler : NSObject

// Shared instance
+ (instancetype)shared;

// Start a crawl. Calls progress on main queue, completion on main queue.
- (void)crawlJob:(VLCrawlJob *)job
        progress:(nullable VLCrawlerProgressBlock)progress
      completion:(VLCrawlerCompletionBlock)completion;

// Cache management
- (NSArray<VLVideoResult *> *)allCachedResults;
- (NSArray<VLVideoResult *> *)cachedResultsForRootURL:(NSString *)url;
- (void)clearCacheForRootURL:(NSString *)url;
- (void)clearAllCache;
- (void)saveCacheToDisk;
- (void)loadCacheFromDisk;

// Persistence path
+ (NSString *)cachePath;

@end

NS_ASSUME_NONNULL_END
