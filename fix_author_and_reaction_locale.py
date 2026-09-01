#!/usr/bin/env python3
import sys

# --- 1. control: change author from "You" to "kitalev" ---
control_path = "control"
with open(control_path, encoding="utf-8") as f:
    control = f.read()

control_old = "Maintainer: You\nAuthor: You"
control_new = "Maintainer: kitalev\nAuthor: kitalev"

if control_old in control:
    control = control.replace(control_old, control_new)
    with open(control_path, "w", encoding="utf-8") as f:
        f.write(control)
    print("OK: control updated (author -> kitalev).")
else:
    print("SKIP: control - expected 'Maintainer: You / Author: You' block not found (already changed?).")

# --- 2. GHLocalization.m: add missing English translations ---
loc_path = "GHLocalization.m"
with open(loc_path, encoding="utf-8") as f:
    loc = f.read()

marker = '            @"Назад": @"Back",\n        };'
addition = ('            @"Назад": @"Back",\n\n'
            '            @"Нужен вход": @"Sign-in required",\n'
            '            @"Чтобы оставить реакцию, войдите в аккаунт в настройках.": '
            '@"Sign in from Settings to leave a reaction.",\n'
            '        };')

if '@"Нужен вход"' in loc:
    print("SKIP: GHLocalization.m - translation already present.")
elif marker in loc:
    loc = loc.replace(marker, addition)
    with open(loc_path, "w", encoding="utf-8") as f:
        f.write(loc)
    print("OK: GHLocalization.m updated (added missing translations).")
else:
    print("ERROR: GHLocalization.m - anchor block not found, no changes made. Send the end of the translations dictionary and I'll adjust the script.")
    sys.exit(1)
