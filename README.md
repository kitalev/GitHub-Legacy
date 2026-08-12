<p align="center">
  <a href="README.md"><b>English</b></a> ·
  <a href="README.ru.md">Русский</a>
</p>

# GitHub Legacy

A native GitHub client for **iOS 6 – iOS 10**, built for jailbroken 32‑bit
devices that the official GitHub app abandoned long ago. Written in plain
Objective‑C (no ARC issues, no frameworks newer than iOS 6), so an old
iPhone or iPad can browse repos, read issues/PRs, and download releases
without opening Safari.

> Built with [Theos](https://theos.dev/) for `armv7`, min. `iPhoneOS 6.0`.
> Requires a jailbreak.

## Features

- **Explore / Search / Starred / Profile** tabs, same layout as the
  original GitHub app.
- **Repository screen** — owner, releases, commits, issues, pull requests,
  star/unstar, and a fully rendered **README** (Markdown → native HTML,
  with clickable commit/issue/PR/release links, dark/light theme).
- **Issues & PRs** — full detail screens with comment threads, paginated
  lists.
- **Releases** — browse changelogs, download assets with progress.
- **Settings** — light/dark theme and English/Russian language, both
  switchable at runtime; sign in with a Personal Access Token.

## Requirements

- iOS 6.0 – 10.x, jailbroken
- `armv7` (32‑bit) only — 64‑bit‑only devices aren't supported

## Installation

Grab a `.deb` from [Releases](../../releases) and install it with
`dpkg -i` over SSH, or open it in Filza/iFile and tap **Install**. Or build
it yourself:

```bash
export THEOS=/opt/theos
cd githublegacy
make package FINALPACKAGE=1
```

Needs an iOS SDK ≥ 6.0 in `$THEOS/sdks/`; adjust the SDK version in
`TARGET =` in the `Makefile` to whatever you have installed.

## Signing in

No OAuth app needed — generate a **Tokens (classic)** on github.com
(**Settings → Developer settings → Personal access tokens → Tokens (classic)**), paste it
into the app's **Sign in** screen. Search and releases work without
signing in too, within GitHub's anonymous rate limit.


## Contributing

Issues and PRs welcome, especially reports from real old devices.

## License

Not yet chosen — all rights reserved until one is added.
