![GitHub Legacy icon](Resources/Icon@2x.png)

# GitHub Legacy

![Platform](https://img.shields.io/badge/platform-iOS%205%E2%80%9310-lightgrey)
![Language](https://img.shields.io/badge/language-Objective--C-blue)
![Build](https://img.shields.io/badge/build-Theos-orange)
[![Release](https://img.shields.io/github/v/release/kitalev/GitHub-Legacy?label=release)](https://github.com/kitalev/GitHub-Legacy/releases/latest)
[![License](https://img.shields.io/badge/license-MIT-green)](LICENSE)
[![Telegram](https://img.shields.io/badge/Telegram-kitalev-26A5E4?logo=telegram&logoColor=white)](https://t.me/kitalev)

**English** · [Русский](README.ru.md)

---

A lightweight native GitHub client for iOS 5–10: repositories, READMEs, issues, pull requests, commits, and releases — without Safari, and without the official app, which no longer runs on these versions.

## Features

- Browse repositories, explore trending projects, and search by name, topic, or user
- View rendered READMEs, issues, pull requests, and full commit history
- Download release assets directly on-device (`.deb`, `.ipa`, source archives, etc.)
- Star repositories and follow users, with a dedicated tab for starred-repo release news
- Light and dark themes, with an in-app English/Russian language switch

## Supported devices

The app is built as a universal binary with two slices:

| Slice | iOS | Devices |
|---|---|---|
| `armv7` (32-bit) | 5.0–10.x | iPhone 3GS, 4, 4S, 5, 5c · iPod touch 4th and 5th gen · iPad 2, 3, 4, iPad mini |
| `arm64` (64-bit) | 7.0–10.x | iPhone 5s, 6, 6 Plus, 6s, 6s Plus, SE, 7, 7 Plus · iPod touch 6th gen · iPad Air, Air 2, iPad mini 2/3/4, iPad Pro, iPad (2017) |

Developed and tested on an **iPhone 4S running iOS 5.1.1**. The 64-bit slice compiles from the same code but hasn't been tested on a device yet.

## Install

### From latest release (.deb)

1. Download `.deb` from the [latest release](https://github.com/kitalev/GitHub-Legacy/releases/latest).
2. Put the `.deb` file on your device (for example: `/var/mobile/`).
3. In iFile or Filza, find the `.deb`, tap it, and press `Install`.

Or via terminal:

```bash
dpkg -i com.githublegacy.app_iphoneos-arm.deb
```

### From latest release (.ipa)

Download `.ipa` from the [latest release](https://github.com/kitalev/GitHub-Legacy/releases/latest) and sideload it with your tool of choice (AltStore, Sideloadly, etc.). No jailbreak required.

> **Note:** on some iOS 10.x devices, Filza can crash while installing the `.ipa`. If that happens, install the `.deb` instead (see above), or use another sideloading tool for the `.ipa`.

## Build

Requires **Theos**, with `THEOS` pointing to its install path:

```bash
export THEOS=/opt/theos
```

You'll also need a Clang toolchain targeting iOS (e.g. `$THEOS/toolchain/linux/iphone/bin`) and an iOS SDK ≥ 5.0 under `$THEOS/sdks/`. Any SDK from 5.0 up works, since `MinimumOSVersion` in `Info.plist` already restricts the app to iOS 5+ at runtime.

```bash
# .deb (unsandboxed, for jailbroken devices via Cydia)
make clean
make package FINALPACKAGE=1

# .ipa (regular sandboxed app, sideloadable)
make clean
make package FINALPACKAGE=1 PACKAGE_FORMAT=ipa
```

Built packages land in `packages/`.

## Uninstall

### Via Cydia

Just remove it like any other package.

### Via terminal

```bash
dpkg -r com.githublegacy.app
```

## License

[MIT](LICENSE)
