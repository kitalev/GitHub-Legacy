![GitHub Legacy icon](Resources/Icon@2x.png)

# GitHub Legacy

![Platform](https://img.shields.io/badge/platform-iOS%206%E2%80%9310-lightgrey)
![Language](https://img.shields.io/badge/language-Objective--C-blue)
![Build](https://img.shields.io/badge/build-Theos-orange)
[![Release](https://img.shields.io/github/v/release/kitalev/GitHub-Legacy?label=release)](https://github.com/kitalev/GitHub-Legacy/releases/latest)
[![License](https://img.shields.io/badge/license-MIT-green)](LICENSE)
[![Telegram](https://img.shields.io/badge/Telegram-kitalev-26A5E4?logo=telegram&logoColor=white)](https://t.me/kitalev)

**English** · [Русский](README.ru.md)

---

A lightweight native GitHub client for iOS 6–10: repositories, READMEs, issues, pull requests, commits, and releases — without Safari, and without the official app, which no longer runs on these versions.

## Features

- Browse repositories, explore trending projects, and search by name, topic, or user
- View rendered READMEs, issues, pull requests, and full commit history
- Download release assets directly on-device (`.deb`, `.ipa`, source archives, etc.)
- Star repositories and follow users, with a dedicated tab for starred-repo release news
- Light and dark themes, with an in-app English/Russian language switch

## Install

### From latest release (.deb)

1. Download `.deb` from the [latest release](https://github.com/kitalev/GitHub-Legacy/releases/latest).
2. Put the `.deb` file on your device (for example: `/var/mobile/`).
3. In iFile, find the `.deb`, tap it, and press `Install`.

Or via terminal:

```bash
dpkg -i com.githublegacy.app_iphoneos-arm.deb
```

### From latest release (.ipa)

Download `.ipa` from the [latest release](https://github.com/kitalev/GitHub-Legacy/releases/latest) and sideload it with your tool of choice (AltStore, Sideloadly, etc.). No jailbreak required.

## Build

Requires **Theos**, with `THEOS` pointing to its install path:

```bash
export THEOS=/opt/theos
```

You'll also need a Clang toolchain targeting iOS (e.g. `$THEOS/toolchain/linux/iphone/bin`) and an iOS SDK ≥ 6.0 under `$THEOS/sdks/`. iOS 6.1 SDKs aren't distributed separately from Xcode anymore; a newer SDK works too, since `MinimumOSVersion` in `Info.plist` already restricts the app to iOS 6+ at runtime.

```bash
# .deb (unsandboxed, for jailbroken devices via Cydia/Sileo)
make clean
make package FINALPACKAGE=1

# .ipa (regular sandboxed app, sideloadable)
make clean
make package FINALPACKAGE=1 PACKAGE_FORMAT=ipa
```

Built packages land in `packages/`.

## Uninstall

### Via Cydia/Sileo

Just remove it like any other package.

### Via terminal

```bash
dpkg -r com.githublegacy.app
```

## License

[MIT](LICENSE)
