![GitHub Legacy icon](Resources/Icon@2x.png)

# GitHub Legacy

![Platform](https://img.shields.io/badge/platform-iOS%205%2B-lightgrey)
![Arch](https://img.shields.io/badge/arch-armv7%20%7C%20arm64-lightgrey)
![Language](https://img.shields.io/badge/language-Objective--C-blue)
![Build](https://img.shields.io/badge/build-Theos-orange)
[![Release](https://img.shields.io/github/v/release/kitalev/GitHub-Legacy?label=release)](https://github.com/kitalev/GitHub-Legacy/releases/latest)
[![License](https://img.shields.io/badge/license-MIT-green)](LICENSE.ru.md)

[English](README.md) · **Русский**

---

Лёгкий нативный клиент GitHub для iOS 5 и новее: репозитории, README, issues, pull request'ы, коммиты и релизы — без Safari и без официального приложения, которое на этих версиях уже не запустить.

## Возможности

- Просмотр репозиториев, популярных проектов и поиск по названию, теме или пользователю
- Отрисованные README, issues, pull request'ы и полная история коммитов
- Скачивание файлов релизов прямо на устройство (`.deb`, `.ipa`, исходники и т.д.)
- Избранные репозитории и подписки на пользователей, отдельная вкладка с новостями релизов из избранного
- Светлая и тёмная темы, переключение языка приложения прямо в настройках

## Поддерживаемые устройства

| Архитектура | iOS | Устройства |
|---|---|---|
| `armv7` (32 бита) | 5.0–10.x | iPhone 3GS, 4, 4S, 5, 5c · iPod touch 4-го и 5-го поколения · iPad 2, 3, 4, iPad mini |
| `arm64` (64 бита) | 7.0 и новее | iPhone 5s и все более новые iPhone · iPod touch 6-го и 7-го поколения · iPad Air и новее, iPad mini 2 и новее, все iPad Pro |

Какой пакет ставить:

| Пакет | Тип джейлбрейка | Обычно iOS | Внутри |
|---|---|---|---|
| `com.githublegacy.app_*_iphoneos-arm.deb` | rootful (Cydia, unc0ver, checkra1n, Taurine, palera1n rootful) | 5.0–14.x, также rootful 15–16 | `armv7` + `arm64`, твик Safari ещё и `arm64e` |
| `com.githublegacy.app_*_iphoneos-arm64.deb` | rootless (Dopamine, palera1n rootless) | 15.0 и новее | `arm64`, твик Safari ещё и `arm64e` |
| `.ipa` | без джейлбрейка (AltStore, Sideloadly, TrollStore) | любая поддерживаемая | `armv7` + `arm64` |

Разрабатывалось и проверялось на **iPhone 4S с iOS 5.1.1**. 64-битные сборки собираются из того же кода, но на устройстве пока не проверялись. Часть твика Safari для `arm64e` собрана под новый ABI, поэтому на iPhone XS и новее он загружается на iOS 14+. На iOS 12–13 на этих устройствах приложение работает, но переход из Safari — нет.

## Установка

### Из последнего релиза (.deb)

1. Скачайте `.deb` под свой тип джейлбрейка со страницы [последнего релиза](https://github.com/kitalev/GitHub-Legacy/releases/latest): `iphoneos-arm` для rootful, `iphoneos-arm64` для rootless (см. таблицу выше).
2. Поместите файл `.deb` на устройство (например, в `/var/mobile/`).
3. В iFile или Filza найдите `.deb`, нажмите на него и выберите `Install`.

Либо через терминал:

```bash
dpkg -i com.githublegacy.app_1.1_iphoneos-arm.deb      # rootful
dpkg -i com.githublegacy.app_1.1_iphoneos-arm64.deb    # rootless
```

### Из последнего релиза (.ipa)

Скачайте `.ipa` со страницы [последнего релиза](https://github.com/kitalev/GitHub-Legacy/releases/latest) и установите любым инструментом сайдлоада (AltStore, Sideloadly и т.д.). Джейлбрейк не требуется.

> **Примечание:** на некоторых устройствах с iOS 10.x Filza может крашиться при установке `.ipa`. В этом случае поставьте `.deb` (см. выше), либо используйте для `.ipa` другой инструмент сайдлоада.

## Сборка

Нужен **Theos**, с переменной `THEOS`, указывающей на его путь:

```bash
export THEOS=/opt/theos
```

Также понадобится Clang-toolchain с таргетингом на iOS (например, `$THEOS/toolchain/linux/iphone/bin`) и iOS SDK ≥ 5.0 в `$THEOS/sdks/`. Подойдёт любой SDK начиная с 5.0, так как `MinimumOSVersion` в `Info.plist` уже ограничивает приложение устройствами с iOS 5+ во время выполнения.

```bash
# rootful .deb (iphoneos-arm: armv7 + arm64)
make clean
make package FINALPACKAGE=1

# rootless .deb (iphoneos-arm64, ставится в /var/jb)
make clean
make package FINALPACKAGE=1 THEOS_PACKAGE_SCHEME=rootless

# .ipa (обычное сандбоксное приложение, для сайдлоада)
make clean
make package FINALPACKAGE=1 PACKAGE_FORMAT=ipa
```

Готовые пакеты появятся в `packages/`.

## Удаление

### Через Cydia

Удаляется как обычный пакет.

### Через терминал

```bash
dpkg -r com.githublegacy.app
```

## Лицензия

[MIT](LICENSE.ru.md) (неофициальный перевод; оригинал — [LICENSE](LICENSE))
