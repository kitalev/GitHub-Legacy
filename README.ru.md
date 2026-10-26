![GitHub Legacy icon](Resources/Icon@2x.png)

# GitHub Legacy

![Platform](https://img.shields.io/badge/platform-iOS%204%2B-lightgrey)
![Arch](https://img.shields.io/badge/arch-armv6%20%7C%20armv7%20%7C%20arm64-lightgrey)
![Language](https://img.shields.io/badge/language-Objective--C-blue)
![Build](https://img.shields.io/badge/build-Theos-orange)
[![Release](https://img.shields.io/badge/release-v2.0-blue)](https://github.com/kitalev/GitHub-Legacy/releases/latest)
[![License](https://img.shields.io/badge/license-MIT-green)](LICENSE.ru.md)
[![Telegram](https://img.shields.io/badge/Telegram-kitalev-26A5E4?logo=telegram&logoColor=white)](https://t.me/kitalev)

[English](README.md) · **Русский**

---

Лёгкий нативный клиент GitHub для iOS 4 и новее: репозитории, README, issues, pull request'ы, коммиты и релизы — без Safari и без официального приложения, которое на старых версиях уже не запустить.

## Возможности

- Просмотр репозиториев, популярных проектов и поиск по названию, теме или пользователю
- Отрисованные README, issues, pull request'ы и полная история коммитов
- Создание задач с прикреплёнными фото и файлами
- Поиск по файлу с кодом
- Недавно открытые репозитории на экране поиска
- Скачивание файлов релизов прямо на устройство (`.deb`, `.ipa`, исходники и т.д.)
- Избранные репозитории и подписки на пользователей, отдельная вкладка с новостями релизов из избранного
- Вход по логину и паролю, через аккаунт Google, GitHub device login или токен
- Светлая и тёмная темы, переключение языка приложения прямо в настройках

## Поддерживаемые устройства

| Архитектура | iOS | Устройства |
|---|---|---|
| `armv6` (32 бита) | 4.0–4.2.1 | iPhone 3G · iPod touch 2-го поколения |
| `armv7` (32 бита) | 4.0–10.x | iPhone 3GS, 4, 4S, 5, 5c · iPod touch 3-го, 4-го и 5-го поколения · iPad 1, 2, 3, 4, iPad mini |
| `arm64` (64 бита) | 7.0 и новее | iPhone 5s и все более новые iPhone · iPod touch 6-го и 7-го поколения · iPad Air и новее, iPad mini 2 и новее, все iPad Pro |

Какой пакет ставить:

| Пакет | Тип джейлбрейка | Обычно iOS | Внутри |
|---|---|---|---|
| `GitHubLegacy_*_rootful_iOS4-14.deb` | rootful (Cydia, unc0ver, checkra1n, Taurine, palera1n rootful) | 4.0–14.x (до iPhone 12), также rootful 15–16 на A8–A11 | `armv6` + `armv7` + `arm64`, твик Safari ещё и `arm64e` |
| `GitHubLegacy_*_rootless_iOS15+.deb` | rootless (Dopamine, palera1n rootless) | 15.0 и новее | `arm64`, твик Safari ещё и `arm64e` |
| `GitHubLegacy_*.ipa` | без джейлбрейка (TrollStore, AltStore, Sideloadly, Plume Impactor) | любая поддерживаемая | `armv6` + `armv7` + `arm64`, без твика Safari |

## Установка

### Из репозитория (рекомендуется)

Добавьте репозиторий в Cydia, Sileo, Zebra или Installer:

```
https://kitalev.github.io/repo/
```

- **Cydia:** Источники → Изменить → Добавить
- **Sileo / Zebra:** Источники → `+`

Затем найдите **GitHub Legacy** и установите. Обновления будут приходить через менеджер пакетов, как у любого другого пакета.

### Из последнего релиза (.deb)

1. Скачайте `.deb` под свой тип джейлбрейка со страницы [последнего релиза](https://github.com/kitalev/GitHub-Legacy/releases/latest): `rootful` или `rootless` (см. таблицу выше).
2. Поместите файл `.deb` на устройство (например, в `/var/mobile/`).
3. В iFile или Filza найдите `.deb`, нажмите на него и выберите `Install`.

Либо через терминал:

```bash
dpkg -i GitHubLegacy_2.0_rootful_iOS4-14.deb    # rootful
dpkg -i GitHubLegacy_2.0_rootless_iOS15+.deb    # rootless
```

### Из последнего релиза (.ipa)

Скачайте `.ipa` со страницы [последнего релиза](https://github.com/kitalev/GitHub-Legacy/releases/latest) и установите через TrollStore, AltStore, Sideloadly, Plume Impactor или Filza / iFile с AppSync Unified. Для инструментов сайдлоада джейлбрейк не нужен.

- На iOS 16 и новее для таких приложений нужен режим разработчика: Настройки → Конфиденциальность и безопасность → Режим разработчика.
- У `.ipa` свой идентификатор (`com.githublegacy.ipa`), поэтому её можно поставить рядом с `.deb`-версией. Вход в аккаунт у каждой свой.

> **Примечание:** на некоторых устройствах с iOS 10.x Filza может крашиться при установке `.ipa`. В этом случае поставьте `.deb` (см. выше), либо используйте для `.ipa` другой инструмент сайдлоада.

## Сборка

Нужен **Theos**, с переменной `THEOS`, указывающей на его путь:

```bash
export THEOS=/opt/theos
```

Также понадобятся:

- Clang-toolchain с таргетингом на iOS (например, `$THEOS/toolchain/linux/iphone/bin`);
- `iPhoneOS9.3.sdk` в `$THEOS/sdks/` — Makefile собирает с ним и сам делает из него копию с поддержкой `armv6`;
- `plistutil` (`sudo apt install libplist-utils`) — для перевода `Info.plist` в бинарный формат и смены идентификатора `.ipa`.

`MinimumOSVersion` в `Info.plist` ограничивает приложение устройствами с iOS 4+ во время выполнения.

```bash
# rootful .deb (iphoneos-arm: armv6 + armv7 + arm64)
make clean
make package FINALPACKAGE=1

# rootless .deb (iphoneos-arm64, ставится в /var/jb)
make clean
make package FINALPACKAGE=1 THEOS_PACKAGE_SCHEME=rootless

# .ipa (обычное приложение для сайдлоада) — появится как GitHubLegacy.ipa в корне проекта
make clean
make ipa FINALPACKAGE=1 PACKAGE_FORMAT=ipa
```

Готовые `.deb` появятся в `packages/`.

## Удаление

### Через Cydia, Sileo или Zebra

Удаляется как обычный пакет.

### Через терминал

```bash
dpkg -r com.githublegacy.app
```

## Лицензия

[MIT](LICENSE.ru.md) (неофициальный перевод; оригинал — [LICENSE](LICENSE))
