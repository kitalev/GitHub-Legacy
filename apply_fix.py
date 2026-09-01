#!/usr/bin/env python3
import sys

path = "DownloadManager.m"

old = '''    // /private/var/mobile/Media/Downloads is only writable from an
    // unsandboxed (jailbreak/.deb) install. A regular .ipa runs inside its
    // own App Container and gets Cocoa error 513 (permission denied) trying
    // to write there. Use a "Downloads" folder inside the app's own home
    // directory instead, which is writable in both cases.
    NSString *downloadsPath = [NSHomeDirectory() stringByAppendingPathComponent:@"Downloads"];

    NSFileManager *fm = [NSFileManager defaultManager];
    BOOL isDirectory = NO;
    BOOL exists = [fm fileExistsAtPath:downloadsPath isDirectory:&isDirectory];'''

new = '''    NSString *standardPath = @"/var/mobile/Media/Downloads";
    NSFileManager *fm = [NSFileManager defaultManager];

    BOOL isDirectory = NO;
    BOOL exists = [fm fileExistsAtPath:standardPath isDirectory:&isDirectory];
    if (!exists) {
        NSError *createError = nil;
        [fm createDirectoryAtPath:standardPath
       withIntermediateDirectories:YES
                        attributes:nil
                             error:&createError];
        exists = [fm fileExistsAtPath:standardPath isDirectory:&isDirectory];
    }

    if (exists && isDirectory && [fm isWritableFileAtPath:standardPath]) {
        return standardPath;
    }

    NSString *downloadsPath = [NSHomeDirectory() stringByAppendingPathComponent:@"Downloads"];

    isDirectory = NO;
    exists = [fm fileExistsAtPath:downloadsPath isDirectory:&isDirectory];'''

with open(path, encoding="utf-8") as f:
    content = f.read()

if old not in content:
    print("ERROR: exact block not found - file differs from expected, no changes made.")
    sys.exit(1)

content = content.replace(old, new)

with open(path, "w", encoding="utf-8") as f:
    f.write(content)

print("OK: DownloadManager.m updated.")
