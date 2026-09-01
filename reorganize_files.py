#!/usr/bin/env python3
import subprocess
import sys
import os

CONTROLLERS = [
    "ExploreViewController", "RepoSearchViewController", "RepoOverviewViewController",
    "RepoDetailViewController", "ReleaseDetailViewController", "StarredReposViewController",
    "ProfileViewController", "CommitHistoryViewController", "CommitDetailViewController",
    "ReadmeViewController", "IssueListViewController", "IssueDetailViewController",
    "PullRequestListViewController", "PullRequestDetailViewController", "ForkListViewController",
    "RepoFilesViewController", "SettingsViewController", "ProfileRepoListViewController",
    "GHUserListViewController", "PublicProfileViewController", "TokenLoginViewController",
    "LanguageViewController",
]

CELLS = ["GHIssueCell", "GHPullRequestCell", "GHStarredRepoCell", "GHExploreFeedCell"]

CORE = [
    "GHTrendingClient", "GHAPIClient", "GHAuthManager", "GHMarkdownRenderer",
    "DownloadManager", "GHAvatarLoader", "GHThemeManager", "GHIconRenderer",
    "GHLocalization",
]

FOLDER_MAP = {}
for name in CONTROLLERS:
    FOLDER_MAP[name] = "Controllers"
for name in CELLS:
    FOLDER_MAP[name] = "Cells"
for name in CORE:
    FOLDER_MAP[name] = "Core"

def run(cmd):
    print("+", " ".join(cmd))
    result = subprocess.run(cmd, capture_output=True, text=True)
    if result.returncode != 0:
        print(result.stdout)
        print(result.stderr, file=sys.stderr)
        sys.exit(1)

# 1. Create folders and git mv files
for folder in ["Controllers", "Cells", "Core"]:
    os.makedirs(folder, exist_ok=True)

moved = 0
skipped = 0
for name, folder in FOLDER_MAP.items():
    for ext in [".h", ".m"]:
        src = f"{name}{ext}"
        dst = f"{folder}/{name}{ext}"
        if os.path.exists(src):
            run(["git", "mv", src, dst])
            moved += 1
        elif os.path.exists(dst):
            skipped += 1
        else:
            print(f"WARNING: {src} not found (already moved or renamed?)")

print(f"\nMoved {moved} files, {skipped} already in place.\n")

# 2. Update Makefile: prefix .m paths and add -I search paths
makefile_path = "Makefile"
with open(makefile_path, encoding="utf-8") as f:
    makefile = f.read()

import re

for name, folder in FOLDER_MAP.items():
    pattern = r'(?<![\w/])' + re.escape(name) + r'\.m\b'
    if re.search(r'/' + re.escape(name) + r'\.m\b', makefile):
        continue  # already prefixed
    makefile = re.sub(pattern, f"{folder}/{name}.m", makefile)

old_cflags = "GitHubLegacy_CFLAGS = -fobjc-arc -Iinclude"
new_cflags = "GitHubLegacy_CFLAGS = -fobjc-arc -Iinclude -IControllers -ICells -ICore"
if old_cflags in makefile:
    makefile = makefile.replace(old_cflags, new_cflags)
elif "-IControllers" not in makefile:
    print("WARNING: could not find CFLAGS line to patch automatically - add "
          "'-IControllers -ICells -ICore' to GitHubLegacy_CFLAGS by hand.")

with open(makefile_path, "w", encoding="utf-8") as f:
    f.write(makefile)

print("OK: Makefile updated.")
print("\nNow verify with:\n  cat Makefile\nand then test-build with:\n  make clean && make package FINALPACKAGE=1")
