![GitHub Legacy icon](Resources/Icon@2x.png)

# GitHub Legacy

![Platform](https://img.shields.io/badge/platform-iOS%205%2B-lightgrey)
![Arch](https://img.shields.io/badge/arch-armv7%20%7C%20arm64-lightgrey)
![Language](https://img.shields.io/badge/language-Objective--C-blue)
![Build](https://img.shields.io/badge/build-Theos-orange)
[![Release](https://img.shields.io/github/v/release/kitalev/GitHub-Legacy?label=release)](https://github.com/kitalev/GitHub-Legacy/releases/latest)
[![License](https://img.shields.io/badge/license-MIT-green)](LICENSE)
[![Telegram](https://img.shields.io/badge/Telegram-kitalev-26A5E4?logo=telegram&logoColor=white)](https://t.me/kitalev)

**English** · [Русский](README.ru.md)

---

A lightweight native GitHub client for iOS 5 and newer: repositories, READMEs, issues, pull requests, commits, and releases — without Safari, and without the official app, which no longer runs on these versions.

## Features

- Browse repositories, explore trending projects, and search by name, topic, or user
- View rendered READMEs, issues, pull requests, and full commit history
- Download release assets directly on-device (`.deb`, `.ipa`, source archives, etc.)
- Star repositories and follow users, with a dedicated tab for starred-repo release news
- Light and dark themes, with an in-app English/Russian language switch

## Supported devices

| Architecture | iOS | Devices |
|---|---|---|
| `armv7` (32-bit) | 5.0–10.x | iPhone 3GS, 4, 4S, 5, 5c · iPod touch 4th and 5th gen · iPad 2, 3, 4, iPad mini |
| `arm64` (64-bit) | 7.0 and newer | iPhone 5s and every later iPhone · iPod touch 6th and 7th gen · iPad Air and later, iPad mini 2 and later, every iPad Pro |

Which package to install:

| Package | Jailbreak type | Typical iOS | Contains |
|---|---|---|---|
| `com.githublegacy.app_*_iphoneos-arm.deb` | rootful (Cydia, unc0ver, checkra1n, Taurine, palera1n rootful) | 5.0–14.x, also rootful 15–16 | `armv7` + `arm64`, Safari tweak also `arm64e` |
| `com.githublegacy.app_*_iphoneos-arm64.deb` | rootless (Dopamine, palera1n rootless) | 15.0 and newer | `arm64`, Safari tweak also `arm64e` |
| `.ipa` | none (AltStore, Sideloadly, TrollStore) | any supported version | `armv7` + `arm64` |

Developed and tested on an **iPhone 4S running iOS 5.1.1**. The 64-bit builds compile from the same code but haven't been tested on a device yet. The Safari redirect tweak's `arm64e` slice uses the new arm64e ABI, so on iPhone XS and newer it loads on iOS 14+; on iOS 12–13 on those devices the app works, but the redirect from Safari doesn't.

## Install

### From latest release (.deb)

1. Download the `.deb` for your jailbreak type from the [latest release](https://github.com/kitalev/GitHub-Legacy/releases/latest): `iphoneos-arm` for rootful, `iphoneos-arm64` for rootless (see the table above).
2. Put the `.deb` file on your device (for example: `/var/mobile/`).
3. In iFile or Filza, find the `.deb`, tap it, and press `Install`.

Or via terminal:

```bash
dpkg -i com.githublegacy.app_1.1_iphoneos-arm.deb      # rootful
dpkg -i com.githublegacy.app_1.1_iphoneos-arm64.deb    # rootless
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
# rootful .deb (iphoneos-arm: armv7 + arm64)
make clean
make package FINALPACKAGE=1

# rootless .deb (iphoneos-arm64, installs under /var/jb)
make clean
make package FINALPACKAGE=1 THEOS_PACKAGE_SCHEME=rootless

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
