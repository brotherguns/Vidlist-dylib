# VLCrawler Tweak

Recursive video link crawler injected into VidList (com.vh.vhub).

## What it does

- Adds a floating **antenna button** to VidList's Sources screen
- Tap it → sheet with your saved crawl sources
- Tap **+** → enter a URL, max depth (1–5), and a label
- Crawler fetches pages recursively on the same host, detects video links
  (mp4, m3u8, mpd, webm, mkv, ts, etc.) including JSON-embedded stream URLs
- Results cached to disk in the app sandbox
- Tap any result → Play (AVPlayer), Copy Link, or Open in Safari
- Export all results as .txt via share sheet

## Detected video types
mp4, m4v, m3u8, m3u, mpd, webm, mkv, avi, mov, flv, ts, ogv, 3gp
Plus HLS/DASH detected via JSON keys: `src`, `url`, `file`, `stream`, `hls`, `dash`, `manifest`

## Build

```bash
# Requires Theos installed at $THEOS
export THEOS=/opt/theos   # or wherever yours is

cd VLCrawlerTweak
make package
```

Output: `packages/com.brotherguns.vlcrawler_1.0.0_iphoneos-arm64.deb`

## Inject (no jailbreak / sideload with dylib injection)

1. Build with `make package` to get the `.deb`, then extract the dylib:
   ```bash
   dpkg-deb -x *.deb extracted/
   # dylib is at extracted/Library/MobileSubstrate/DynamicLibraries/VLCrawler.dylib
   ```
2. Inject `VLCrawler.dylib` into `VidList.app` using your preferred method:
   - **Patchelf/insert_dylib**: `insert_dylib --all-yes @rpath/VLCrawler.dylib VidList.app/VidList`
   - Then copy `VLCrawler.dylib` into `VidList.app/Frameworks/`
   - Update `@rpath` in Info.plist `NSPrincipalClass` or add to `LD_RUNPATH_SEARCH_PATHS` if needed
   - Re-sign the app bundle with your cert

3. Re-sign and sideload as usual (Sideloadly / AltStore / etc.)

## Cache location

`<AppDocuments>/VLCrawler_cache.archive`  (NSKeyedArchiver, SecureCoding)

## Notes

- Max links cap is 1000 per job (safety, adjustable in VLCrawler.h)
- 8 concurrent fetches per crawl (adjustable via semaphore count in VLCrawler.m)
- Only follows links on the **same host** – won't crawl off-site
- Skips CSS/JS/image/font assets automatically
- User-Agent spoofed as Safari/iPhone to avoid bot blocks
