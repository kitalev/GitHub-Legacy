#import "GHLocalization.h"

NSString * const kGHLanguageDidChangeNotification = @"GHLanguageDidChangeNotification";

static NSString * const kGHLanguageDefaultsKey = @"GHLanguageCode";

@implementation GHLocalization

+ (instancetype)sharedManager {
    static GHLocalization *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[GHLocalization alloc] init];
    });
    return instance;
}

- (id)init {
    self = [super init];
    if (self) {
        NSString *saved = [[NSUserDefaults standardUserDefaults] stringForKey:kGHLanguageDefaultsKey];

        _languageCode = saved.length > 0 ? saved : @"en";
    }
    return self;
}

- (void)setLanguageCode:(NSString *)languageCode {
    if ([_languageCode isEqualToString:languageCode]) return;
    _languageCode = [languageCode copy];

    [[NSUserDefaults standardUserDefaults] setObject:languageCode forKey:kGHLanguageDefaultsKey];
    [[NSUserDefaults standardUserDefaults] synchronize];

    [[NSNotificationCenter defaultCenter] postNotificationName:kGHLanguageDidChangeNotification object:nil];
}

@end

static NSDictionary *GHTranslations(void) {
    static NSDictionary *translations = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        translations = @{

            @"Обзор": @"Explore",
            @"Поиск": @"Search",
            @"Избранное": @"Starred",

            @"Ошибка": @"Error",
            @"Загрузка…": @"Loading…",
            @"Отмена": @"Cancel",
            @"Войти": @"Sign In",
            @"Выйти": @"Sign Out",
            @"Удалить": @"Delete",
            @"Очистить": @"Clear",
            @"—": @"—",

            @"Настройки": @"Settings",
            @"Аккаунт": @"Account",
            @"Внешний вид": @"Appearance",
            @"О программе": @"About",
            @"Репозиторий на GitHub": @"GitHub Repository",
            @"Тёмная тема": @"Dark Theme",
            @"Язык": @"Language",
            @"Русский": @"Russian",
            @"Английский": @"English",
            @"Выйти из аккаунта": @"Sign Out",
            @"Выйти из аккаунта?": @"Sign out of your account?",
            @"Вход по токену": @"Sign in with Token",
            @"Вставьте токен сюда": @"Paste your token here",
            @"Personal Access Token — это персональный ключ доступа к вашему аккаунту GitHub, который вы создаёте сами на сайте, без входа через встроенный браузер приложения.\n\nСоздать токен можно здесь:\nhttps://github.com/settings/tokens\n\nКак создать токен по шагам:\n\n1. Откройте ссылку выше (или вручную: github.com → Settings → Developer settings → Personal access tokens → Tokens (classic)) и нажмите «Generate new token» → «Generate new token (classic)».\n\n2. В поле «Note» впишите любое понятное название токена — например, название этого телефона или приложения. Оно нужно только вам, чтобы потом узнавать этот токен в списке на github.com.\n\n3. В «Expiration» задайте срок действия — по истечении токен перестанет работать, и потребуется создать новый (по умолчанию стоит «No expiration», то есть без ограничения срока).\n\n4. В «Select scopes» отметьте нужные права. Проще всего отметить галочку «repo» самую первую в списке (Full control of private repositories) — она сразу даёт доступ и на чтение, и на запись ко всем репозиториям, этого достаточно для всех функций приложения, включая добавление в избранное. Если нужен доступ только к публичным репозиториям без приватных, вместо неё можно отметить только «public_repo» (это подпункт внутри «repo»). Остальные галочки не нужны.\n\n5. Нажмите «Generate token» внизу страницы и скопируйте получившийся токен — он показывается только один раз, при следующем открытии страницы вы его уже не увидите.\n\n6. Вернитесь в приложение и вставьте скопированный токен в поле выше.":
                @"A Personal Access Token is your own personal key to your GitHub account, which you create yourself on the website, without signing in through the app's built-in browser.\n\nYou can create a token here:\nhttps://github.com/settings/tokens\n\nHow to create a token, step by step:\n\n1. Open the link above (or navigate manually: github.com → Settings → Developer settings → Personal access tokens → Tokens (classic)) and tap \"Generate new token\" → \"Generate new token (classic)\".\n\n2. In the \"Note\" field, enter any name that makes sense to you — for example, the name of this phone or app. It's only for your own reference, to recognize this token later in the list on github.com.\n\n3. Under \"Expiration\", set how long the token should last — once it expires it stops working and you'll need to create a new one (the default is \"No expiration\", meaning no time limit).\n\n4. Under \"Select scopes\", check the permissions you need. The simplest option is the very first checkbox, \"repo\" (Full control of private repositories) — it grants both read and write access to all repositories, which is enough for every feature in the app, including starring. If you only work with public repositories and don't need private ones, you can check just \"public_repo\" instead (a sub-item under \"repo\"). No other checkboxes are needed.\n\n5. Tap \"Generate token\" at the bottom of the page and copy the resulting token — it's shown only once, you won't be able to see it again after leaving the page.\n\n6. Come back to the app and paste the copied token into the field above.",
            @"Ошибка входа": @"Sign-In Error",
            @"Не удалось войти — проверьте правильность токена и его срок действия.":
                @"Couldn't sign in — check that the token is correct and hasn't expired.",
            @"GitHub Legacy": @"GitHub Legacy",
            @"Лёгкий нативный клиент GitHub для iOS 6–10: репозитории, README на нескольких языках, issues, pull request'ы, коммиты и релизы — без Safari и без официального приложения, которое на этих версиях уже не запустить.\n\nmade by kitalev":
                @"A lightweight native GitHub client for iOS 6–10: repositories, README in multiple languages, issues, pull requests, commits, and releases — without Safari, and without the official app, which no longer runs on these versions.\n\nmade by kitalev",

            @"GitHub Search": @"GitHub Search",
            @"Search": @"Search",
            @"Название репозитория": @"Repository name",
            @"Заголовок issue или pull request": @"Issue or pull request title",
            @"Логин пользователя или организации": @"User or organization login",
            @"Репозитории": @"Repositories",
            @"Задачи/PR": @"Issues/PR",
            @"Люди": @"People",
            @"Организация": @"Organization",
            @"Пользователь": @"User",
            @"Недавние запросы": @"Recent Searches",
            @"Очистить историю": @"Clear History",
            @"Очистить историю поиска?": @"Clear search history?",

            @"Скрыть": @"Hide",

            @"Войдите в аккаунт, чтобы видеть новости о релизах репозиториев в избранном":
                @"Sign in to see release news for your starred repos",
            @"Пока нет новых релизов в избранных репозиториях": @"No new releases in your starred repositories yet",
            @"Новые релизы": @"New releases",
            @"новый релиз": @"new release",
            @"опубликовал релиз": @"released",

            @"сейчас": @"now",
            @"%ldмин": @"%ldm",
            @"%ldч": @"%ldh",
            @"%ldдн": @"%ldd",
            @"%ldмес": @"%ldmo",
            @"%ldг": @"%ldy",

            @"Профиль": @"Profile",
            @"Войдите в аккаунт в Настройках, чтобы видеть свой профиль": @"Sign in from Settings to see your profile",
            @"Открыть настройки": @"Open Settings",
            @"подписчиков": @"followers",
            @"подписок": @"following",
            @"Подписчики": @"Followers",
            @"Подписки": @"Following",
            @"Подписаться": @"Follow",
            @"Отписаться": @"Unfollow",
            @"Не удалось выполнить действие": @"Couldn't complete the action",
            @"Закреплённые": @"Pinned",

            @"Starred": @"Starred",
            @"Войдите в аккаунт, чтобы видеть избранные репозитории": @"Sign in to see your starred repositories",

            @"Подписчиков нет": @"No followers",
            @"Подписок нет": @"No following",

            @"Репозиториев нет": @"No repositories",

            @"Описание": @"Description",
            @"README": @"README",
            @"Загрузка README…": @"Loading README…",
            @"README не найден": @"README not found",
            @"Владелец": @"Owner",
            @"Открыть README полностью →": @"Read Full README →",
            @"Читать полностью →": @"Read Full Description →",
            @"Смотреть релизы": @"View Releases",
            @"История коммитов": @"Commit History",
            @"Задача": @"Issue",
            @"Задачи": @"Issues",
            @"Задачи (%@)": @"Issues (%@)",
            @"Задачи (скрыто)": @"Issues (hidden)",
            @"Пул-реквесты": @"Pull Requests",
            @"Ещё": @"More",
            @"Нет описания": @"No description",
            @"Релизы": @"Releases",

            @"Популярные репозитории": @"Trending repositories",
            @"+%@ за неделю": @"+%@ this week",
            @"★ Проверка…": @"★ Checking…",
            @"★ В избранном (убрать)": @"★ Starred (tap to unstar)",
            @"☆ Добавить в избранное": @"☆ Add to Starred",
            @"Issues скрыты": @"Issues are disabled",
            @"Владелец репозитория отключил раздел Issues — GitHub не отдаёт по нему ни одной issue, поэтому список всегда будет пустым.":
                @"The repository owner has disabled Issues — GitHub won't return any for it, so this list will always be empty.",

            @"Релиз": @"Release",
            @"Файлы": @"Files",
            @"Загрузка описания…": @"Loading description…",
            @"У этого релиза нет описания": @"This release has no description",
            @"Исходный код (zip)": @"Source code (zip)",
            @"Исходный код (tar.gz)": @"Source code (tar.gz)",
            @"Нажмите для скачивания": @"Tap to download",
            @"Скачивание: 0%": @"Downloading: 0%",
            @"Ошибка скачивания": @"Download Error",
            @"Сохранено в Media/Downloads": @"Saved to Media/Downloads",
            @"Скачивание завершено": @"Download Complete",
            @"Открыть в приложении…": @"Open in App…",
            @"Открыть": @"Open",
            @"Нет подходящих приложений": @"No Suitable Apps",
            @"На устройстве не нашлось приложения, заявившего поддержку этого типа файлов.":
                @"No app on this device claims to support this file type.",
            @"Без названия": @"Untitled",

            @"Коммит": @"Commit",
            @"Коммиты": @"Commits",
            @"Не удалось загрузить коммит": @"Failed to load commit",
            @"(без сообщения)": @"(no message)",
            @"строк": @"lines",
            @"строку": @"line",
            @"строки": @"lines",
            @"(файл)": @"(file)",
            @"добавлен": @"added",
            @"удалён": @"removed",
            @"изменён": @"modified",
            @"переименован": @"renamed",

            @"● Открыт": @"● Open",
            @"✓ Закрыт": @"✓ Closed",

            @"⊘ Закрыт: не планируется": @"⊘ Closed as not planned",
            @"⊘ Закрыт как дубликат": @"⊘ Closed as duplicate",
            @"⑂ Слит": @"⑂ Merged",
            @"✕ Закрыт без слияния": @"✕ Closed without merging",
            @"Открытые": @"Open",
            @"Закрытые": @"Closed",
            @"Открытых issues нет": @"No open issues",
            @"Закрытых issues нет": @"No closed issues",
            @"Открытых pull request'ов нет": @"No open pull requests",
            @"Закрытых pull request'ов нет": @"No closed pull requests",
            @"(без заголовка)": @"(no title)",
            @" · Слит": @" · Merged",
            @" · Закрыт без слияния": @" · Closed without merging",
            @"Не удалось загрузить комментарии.": @"Failed to load comments.",

            @"Не удалось создать соединение": @"Failed to create connection",
            @"GraphQL API требует авторизации.": @"The GraphQL API requires authorization.",
            @"Ошибка GraphQL-запроса.": @"GraphQL request error.",
            @"неизвестная ошибка": @"unknown error",
            @"Ошибка (HTTP %ld)": @"Error (HTTP %ld)",
            @"Ошибка: %@": @"Error: %@",
            @"%lu файл(ов)": @"%lu file(s)",
            @"%lu файл(ов) · %.2f МБ": @"%lu file(s) · %.2f MB",
            @"%.2f МБ — нажмите для скачивания": @"%.2f MB — tap to download",
            @"Скачивание: %.0f%%": @"Downloading: %.0f%%",
            @"Показать ещё %ld %@": @"Show %ld more %@",
            @"изображение": @"image",

            @"Форки": @"Forks",
            @"Форки (%@)": @"Forks (%@)",
            @"Период": @"Period",
            @"Сортировка": @"Sort",
            @"Всё время": @"All time",
            @"Последний год": @"Last year",
            @"Последние %ld года": @"Last %ld years",

            @"Последние 2 года": @"Last 2 years",
            @"По звёздам": @"Most starred",
            @"Сначала старые": @"Oldest first",
            @"Сначала новые": @"Newest first",

            @"Папка пуста": @"This folder is empty",
            @"🖼 Открыть изображение": @"🖼 Open Image",

            @"У репозитория пока нет форков": @"This repository doesn't have any forks yet",
            @"За выбранный период форков не найдено — попробуйте расширить период": @"No forks found for the selected period — try widening it",

            @"Назад": @"Back",
        };
    });
    return translations;
}

NSString *GHL(NSString *russianText) {
    if (russianText.length == 0) return russianText;
    if (![[GHLocalization sharedManager].languageCode isEqualToString:@"en"]) return russianText;

    NSString *translated = GHTranslations()[russianText];
    return translated ?: russianText;
}
