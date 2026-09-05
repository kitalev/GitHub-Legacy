![GitHub Legacy icon](Resources/Icon@2x.png)

# GitHub Legacy

![Platform](https://img.shields.io/badge/platform-iOS%206%E2%80%9310-lightgrey)
![Language](https://img.shields.io/badge/language-Objective--C-blue)
![Build](https://img.shields.io/badge/build-Theos-orange)
[![Release](https://img.shields.io/github/v/release/kitalev/GitHub-Legacy?label=release)](https://github.com/kitalev/GitHub-Legacy/releases/latest)
[![License](https://img.shields.io/badge/license-MIT-green)](LICENSE.ru.md)

[English](README.md) · **Русский**

---

Лёгкий нативный клиент GitHub для iOS 6–10: репозитории, README, issues, pull request'ы, коммиты и релизы — без Safari и без официального приложения, которое на этих версиях уже не запустить.

## Возможности

- Просмотр репозиториев, популярных проектов и поиск по названию, теме или пользователю
- Отрисованные README, issues, pull request'ы и полная история коммитов
- Скачивание файлов релизов прямо на устройство (`.deb`, `.ipa`, исходники и т.д.)
- Избранные репозитории и подписки на пользователей, отдельная вкладка с новостями релизов из избранного
- Светлая и тёмная темы, переключение языка приложения прямо в настройках

## Установка

### Из последнего релиза (.deb)

1. Скачайте `.deb` со страницы [последнего релиза](https://github.com/kitalev/GitHub-Legacy/releases/latest).
2. Поместите файл `.deb` на устройство (например, в `/var/mobile/`).
3. В iFile или Filza найдите `.deb`, нажмите на него и выберите `Install`.

Либо через терминал:

```bash
dpkg -i com.githublegacy.app_iphoneos-arm.deb
```

### Из последнего релиза (.ipa)

Скачайте `.ipa` со страницы [последнего релиза](https://github.com/kitalev/GitHub-Legacy/releases/latest) и установите любым инструментом сайдлоада (AltStore, Sideloadly и т.д.). Джейлбрейк не требуется.

> **Примечание:** на некоторых устройствах с iOS 10.x Filza может крашиться при установке `.ipa`. В этом случае поставьте `.deb` (см. выше), либо используйте для `.ipa` другой инструмент сайдлоада.

## Сборка

Нужен **Theos**, с переменной `THEOS`, указывающей на его путь:

```bash
export THEOS=/opt/theos
```

Также понадобится Clang-toolchain с таргетингом на iOS (например, `$THEOS/toolchain/linux/iphone/bin`) и iOS SDK ≥ 6.0 в `$THEOS/sdks/`. Подойдёт любой SDK начиная с 6.0, так как `MinimumOSVersion` в `Info.plist` уже ограничивает приложение устройствами с iOS 6+ во время выполнения.

```bash
# .deb (несандбоксная сборка, для джейлбрейк-устройств через Cydia)
make clean
make package FINALPACKAGE=1

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
