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
            @"Вход": @"Sign In",
            @"Вход через github.com": @"Sign in via github.com",
            @"Войти через github.com": @"Sign in via github.com",
            @"Войти по токену": @"Sign in with a token",
            @"Для входа через github.com/login/device нужен Client ID OAuth-приложения с включённым Device Flow.\n\nСоздать: github.com → Settings → Developer settings → OAuth Apps → New OAuth App → включите «Enable Device Flow». Client Secret не нужен.\n\nВпишите Client ID ниже — он сохранится на этом устройстве.":
                @"Signing in via github.com/login/device needs the Client ID of an OAuth App with Device Flow enabled.\n\nCreate one: github.com → Settings → Developer settings → OAuth Apps → New OAuth App → enable \"Enable Device Flow\". No Client Secret is needed.\n\nEnter the Client ID below — it will be saved on this device.",
            @"Продолжить": @"Continue",
            @"Получение кода…": @"Requesting code…",
            @"Вход отклонён.": @"Sign-in was declined.",
            @"Что-то пошло не так.": @"Something went wrong.",
            @"Не удалось получить код. Проверьте Client ID.": @"Couldn't request a code. Check the Client ID.",
            @"Готово, входим…": @"Done, signing in…",
            @"Не удалось войти после подтверждения. Попробуйте ещё раз.": @"Sign-in failed after confirmation. Please try again.",
            @"Изменить Client ID": @"Change Client ID",
            @"Введите код на github.com": @"Enter the code on github.com",
            @"Скопировать": @"Copy",
            @"Скопировано": @"Copied",
            @"Новый код": @"New code",
            @"1. Откройте github.com/login/device на компьютере или другом телефоне\n2. Введите код, показанный выше\n3. Нажмите «Authorize» — этот экран обновится сам":
                @"1. Open github.com/login/device on a computer or another phone\n2. Enter the code shown above\n3. Tap \"Authorize\" — this screen will update on its own",
            @"Ожидание подтверждения…": @"Waiting for confirmation…",
            @"Код истёк. Получите новый.": @"The code expired. Get a new one.",
            @"Код действует ещё %ld:%02ld": @"Code expires in %ld:%02ld",
            @"Вход выполнен": @"You're signed in",
            @"Вы вошли как @%@.\nЭто устройство подключено к вашему аккаунту GitHub.": @"Signed in as @%@.\nThis device is now connected to your GitHub account.",
            @"Готово": @"Done",
            @"Вход в GitHub": @"Sign in to GitHub",
            @"Выберите, как войти в аккаунт": @"Choose how you'd like to sign in",
            @"Рекомендуется": @"Recommended",
            @"Другой способ": @"Other option",
            @"Введите короткий код на github.com/login/device с компьютера или другого телефона. Пароль приложение не видит.":
                @"Enter a short code at github.com/login/device from a computer or another phone. The app never sees your password.",
            @"Вставьте Personal Access Token, созданный вручную на github.com.": @"Paste a Personal Access Token you created on github.com.",
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
            @"Ключ доступа, который вы создаёте сами на github.com": @"An access key you create yourself on github.com",
            @"Вставить": @"Paste",
            @"Как получить токен": @"How to get a token",
            @"1. Откройте github.com/settings/tokens — удобнее с компьютера\n2. Generate new token → Generate new token (classic)\n3. Note — любое название, например «iPhone 4S»\n4. Expiration — срок действия; по истечении нужен новый токен\n5. Scopes — отметьте «repo» и «user:follow». Если приватные репозитории не нужны, вместо «repo» хватит «public_repo»\n6. Generate token — скопируйте токен и вставьте выше. GitHub покажет его только один раз":
                @"1. Open github.com/settings/tokens — easier from a computer\n2. Generate new token → Generate new token (classic)\n3. Note — any name, e.g. \"iPhone 4S\"\n4. Expiration — how long it stays valid; you'll need a new token after that\n5. Scopes — check \"repo\" and \"user:follow\". If you don't need private repositories, \"public_repo\" is enough instead of \"repo\"\n6. Generate token — copy it and paste it above. GitHub shows it only once",
            @"Открыть github.com/settings/tokens": @"Open github.com/settings/tokens",
            @"В буфере обмена ничего нет.": @"The clipboard is empty.",
            @"Проверка токена…": @"Checking token…",
            @"Не удалось войти — проверьте правильность токена и его срок действия.":
                @"Couldn't sign in — check that the token is correct and hasn't expired.",
            @"GitHub Legacy": @"GitHub Legacy",
            @"Лёгкий нативный клиент GitHub для iOS 5–10: репозитории, README на нескольких языках, issues, pull request'ы, коммиты и релизы — без Safari и без официального приложения, которое на этих версиях уже не запустить.\n\nmade by kitalev":
                @"A lightweight native GitHub client for iOS 5–10: repositories, README in multiple languages, issues, pull requests, commits, and releases — without Safari, and without the official app, which no longer runs on these versions.\n\nmade by kitalev",

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
            @"Организации": @"Organizations",
            @"%ld выполняется": @"%ld in progress",
            @"%ld с ошибкой": @"%ld failing",
            @"%ld успешно": @"%ld successful",
            @"Ветка отстаёт": @"Branch is out of date",
            @"Все проверки пройдены": @"All checks have passed",
            @"Есть конфликты": @"This branch has conflicts",
            @"Закрыт без слияния": @"Closed without merging",
            @"Запрошены изменения": @"Changes requested",
            @"Изменения": @"Changes",
            @"Изменения влиты в %@": @"Merged into %@",
            @"Изменения одобрены": @"Changes approved",
            @"Их нужно разрешить перед слиянием": @"They must be resolved before merging",
            @"Конфликтов с базовой веткой нет": @"No conflicts with the base branch",
            @"Можно слить": @"Ready to merge",
            @"Не выполнены обязательные условия": @"Required conditions have not been met",
            @"Не удалось загрузить pull request.": @"Couldn't load the pull request.",
            @"Некоторые проверки не прошли": @"Some checks were not successful",
            @"Но некоторые проверки не прошли": @"But some checks were not successful",
            @"Нужно обновить её от %@": @"Update it from %@",
            @"Обсуждение": @"Conversation",
            @"Пока никто не оставил отзыв": @"No reviews yet",
            @"Проверки выполняются": @"Checks are running",
            @"Ревью": @"Reviews",
            @"Слит": @"Merged",
            @"Слияние заблокировано": @"Merging is blocked",
            @"Слияние недоступно, пока пул-реквест в черновике": @"Merging is unavailable while the pull request is a draft",
            @"Статус": @"Status",
            @"Черновик": @"Draft",
            @"закрыл(а) пул-реквест": @"closed this",
            @"запросил(а) изменения": @"requested changes",
            @"запросил(а) отзыв у %@": @"requested a review from %@",
            @"одобрил(а) изменения": @"approved these changes",
            @"оставил(а) отзыв": @"reviewed these changes",
            @"отзыв отклонён": @"review dismissed",
            @"отметил(а) как готовый к ревью": @"marked this as ready for review",
            @"перевёл(а) в черновик": @"converted this to a draft",
            @"слил(а) коммит %@": @"merged commit %@",
            @"слил(а) пул-реквест": @"merged this",
            @"снова открыл(а) пул-реквест": @"reopened this",
            @"удалил(а) ветку": @"deleted the branch",
            @"✕ Закрыт": @"✕ Closed",
            @"Контрибьютор": @"Contributor",
            @"Соавтор": @"Collaborator",
            @"Участник": @"Member",
            @"Не удалось загрузить issue.": @"Couldn't load the issue.",
            @"Описание не добавлено.": @"No description provided.",
            @"добавил(а) метку %@": @"added the %@ label",
            @"убрал(а) метку %@": @"removed the %@ label",
            @"закрыл(а) задачу как выполненную": @"closed this as completed",
            @"закрыл(а) задачу как дубликат": @"closed this as a duplicate",
            @"закрыл(а) задачу как не планируемую": @"closed this as not planned",
            @"снова открыл(а) задачу": @"reopened this",
            @"изменил(а) заголовок: <s>%@</s> → <b>%@</b>": @"changed the title <s>%@</s> → <b>%@</b>",
            @"назначил(а) %@": @"assigned %@",
            @"снял(а) назначение с %@": @"unassigned %@",
            @"упомянул(а) задачу в %@": @"mentioned this in %@",
            @"● Открыта": @"● Open",
            @"⊘ Закрыта": @"⊘ Closed",
            @"✓ Закрыта": @"✓ Closed",
            @"В избранное": @"Star",
            @"В избранном": @"Starred",
            @"Не удалось проверить": @"Couldn't check",
            @"Не удалось проверить, добавлен ли репозиторий в избранное: %@": @"Couldn't check whether the repository is starred: %@",
            @"Код": @"Code",
            @"Лицензия": @"License",
            @"Последний": @"Latest",
            @"Текущая ветка": @"Current branch",
            @"скрыты": @"hidden",
            @"Организаций нет": @"No organizations",

            @"Репозиториев нет": @"No repositories",

            @"Описание": @"Description",
            @"README": @"README",
            @"Загрузка README…": @"Loading README…",
            @"README не найден": @"README not found",
            @"Владелец": @"Owner",
            @"Открыть README полностью →": @"Read Full README →",
            @"Читать полностью →": @"Read Full Description →",
            @"Задача": @"Issue",
            @"Задачи": @"Issues",
            @"Пул-реквесты": @"Pull Requests",
            @"Ещё": @"More",
            @"Релизы": @"Releases",

            @"Популярные репозитории": @"Trending repositories",
            @"+%@ за неделю": @"+%@ this week",
            @"Issues скрыты": @"Issues are disabled",
            @"Владелец репозитория отключил раздел Issues — GitHub не отдаёт по нему ни одной issue, поэтому список всегда будет пустым.":
                @"The repository owner has disabled Issues — GitHub won't return any for it, so this list will always be empty.",

            @"Релиз": @"Release",
            @"Все релизы": @"All Releases",
            @"Нет релизов": @"No releases",
            @"Последний релиз": @"Latest release",
            @"Пре-релиз": @"Pre-release",
            @"опубликовал(а) %@": @"released this %@",
            @"Участники": @"Contributors",
            @"Показать всех": @"View all",
            @"Участников: %ld": @"%ld contributors",
            @"Информация": @"Info",
            @"Файлы релиза": @"Assets",
            @"Скачать": @"Download",
            @"Скопировать ссылку": @"Copy link",
            @"Ссылка скопирована": @"Link copied",
            @"Сохранено": @"Saved",
            @"байт": @"bytes",
            @"КБ": @"KB",
            @"МБ": @"MB",
            @"ГБ": @"GB",
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
            @"%lu файл(ов)": @"%lu file(s)",
            @"%lu файл(ов) · %.2f МБ": @"%lu file(s) · %.2f MB",
            @"%.2f МБ — нажмите для скачивания": @"%.2f MB — tap to download",
            @"Скачивание: %.0f%%": @"Downloading: %.0f%%",
            @"Показать ещё %ld %@": @"Show %ld more %@",
            @"изображение": @"image",

            @"Форки": @"Forks",
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

            @"Нужен вход": @"Sign-in required",
            @"Чтобы оставить реакцию, войдите в аккаунт в настройках.": @"Sign in from Settings to leave a reaction.",

            @"Потяните, чтобы обновить": @"Pull to refresh",
            @"Отпустите, чтобы обновить": @"Release to refresh",
            @"Обновление…": @"Refreshing…",

            @"Возможно, у вашего токена нет прав на звёздочки. Для classic-токена нужен scope «public_repo», для fine-grained — разрешение «Starring».": @"Your token may not have permission to star repositories. Classic tokens need the \"public_repo\" scope; fine-grained tokens need the \"Starring\" permission.",
            @"Возможно, у вашего токена нет прав на подписки. Для classic-токена нужен scope «user:follow», для fine-grained — разрешение «Followers».": @"Your token may not have permission to follow users. Classic tokens need the \"user:follow\" scope; fine-grained tokens need the \"Followers\" permission.",

            @"Новая задача": @"New Issue",
            @"Выберите шаблон": @"Choose Template",
            @"Пустая задача": @"Blank issue",
            @"Создать задачу без шаблона.": @"Create a new issue from scratch.",
            @"Заголовок": @"Title",
            @"Опишите задачу. Поддерживается Markdown.": @"Describe the issue. Markdown is supported.",
            @"Создать": @"Submit",
            @"Создать задачу": @"Submit new issue",
            @"Выберите…": @"Select…",
            @"Нет": @"None",
            @"Заполните обязательные поля": @"Fill in the required fields",
            @"Не удалось создать задачу": @"Couldn't create the issue",
            @"Не удалось загрузить шаблоны задач": @"Couldn't load issue templates",
            @"Продолжить без шаблона": @"Continue without a template",
            @"Чтобы создать задачу, войдите в аккаунт в настройках.": @"Sign in from Settings to create an issue.",
            @"Возможно, у вашего токена нет прав на создание задач. Для classic-токена нужен scope «public_repo» (или «repo» для приватных репозиториев), для fine-grained — разрешение «Issues: Read and write».":
                @"Your token may not have permission to create issues. Classic tokens need the \"public_repo\" scope (or \"repo\" for private repositories); fine-grained tokens need the \"Issues: Read and write\" permission.",

            @"Прикрепить фото или файл…": @"Attach a photo or file…",
            @"Фото из медиатеки": @"Photo Library",
            @"Снять фото": @"Take Photo",
            @"Файл…": @"File…",
            @"Проверка доступа…": @"Checking access…",
            @"Загрузка": @"Uploading",
            @"Загрузка… %d%%": @"Uploading… %d%%",
            @"Фото и видео недоступны": @"Photos and videos unavailable",
            @"В %@/%@ у вас нет права записи, а GitHub загружает фото и видео только с привязкой к репозиторию, где такое право есть. Обычно для этого используется ваш собственный публичный репозиторий (в него ничего не добавляется), но у вас его нет.\n\nЛоги и текстовые файлы можно вставить в задачу текстом через «Файл…».":
                @"You don't have write access to %@/%@, and GitHub only uploads photos and videos on behalf of a repository where you do. Normally one of your own public repositories is used for this (nothing is added to it), but you don't have any.\n\nLogs and text files can still be inserted into the issue as text via \"File…\".",
            @"Загрузка через %@… %d%%": @"Uploading via %@… %d%%",
            @"Файл пустой.": @"The file is empty.",
            @"Нет доступа на чтение: файл принадлежит %@ (права %lo), а приложение работает от пользователя mobile. Откройте папку с файлом в файловом менеджере, скопируйте файл, например, в Загрузки и прикрепите копию.":
                @"No read access: the file belongs to %@ (permissions %lo), and the app runs as the mobile user. Open the file's folder in a file manager, copy the file, e.g. to Downloads, and attach the copy.",
            @"Открыть в Filza": @"Open in Filza",
            @"Открыть в iFile": @"Open in iFile",
            @"GitHub не разрешил загрузку: для этого нужно право записи в репозиторий.": @"GitHub refused the upload: it requires write access to the repository.",
            @"GitHub не вернул ссылку на загруженный файл.": @"GitHub didn't return a link to the uploaded file.",
            @"Файл пустой или слишком большой: можно не больше %llu МБ.": @"The file is empty or too large: the limit is %llu MB.",
            @"Не удалось прочитать файл.": @"Couldn't read the file.",
            @"Не удалось подготовить фото.": @"Couldn't prepare the photo.",
            @"Файл ещё загружается": @"A file is still uploading",
            @"Дождитесь окончания загрузки и отправьте задачу ещё раз.": @"Wait for the upload to finish, then submit the issue again.",
            @"Не удалось прикрепить файл": @"Couldn't attach the file",
            @"Этот файл нельзя прикрепить. GitHub принимает фото и видео (%@), а текстовые файлы — логи, конфиги — вставляются в задачу текстом.":
                @"This file can't be attached. GitHub accepts photos and videos (%@); text files such as logs and configs are inserted into the issue as text.",
            @"В тексте задачи не осталось места: GitHub ограничивает его 65 536 символами.":
                @"There's no room left in the issue text: GitHub limits it to 65,536 characters.",
            @"_Показан конец файла: последние %lu строк._\n\n": @"_Showing the end of the file: last %lu lines._\n\n",
            @"Слишком длинный текст": @"Text is too long",
            @"GitHub принимает не больше %lu символов, а в задаче %lu. Сократите текст или вложенные файлы.":
                @"GitHub accepts at most %lu characters, but this issue has %lu. Shorten the text or the attached files.",
            @"Выберите файл": @"Choose File",
            @"Загрузки": @"Downloads",
            @"Загрузки приложения": @"App Downloads",
            @"Медиа": @"Media",
            @"Документы": @"Documents",
            @"Системные логи": @"System Logs",
            @"Корень файловой системы": @"File System Root",
            @"Нет доступа к папке": @"No access to this folder",

            @"Поиск по задачам": @"Search issues",
            @"Поиск по pull request'ам": @"Search pull requests",
            @"Ничего не найдено": @"Nothing found",
            @"Поиск…": @"Searching…",

            @"Ссылки GitHub": @"GitHub Links",
            @"Переадресация": @"Redirect",
            @"Ссылки github.com из Safari и других приложений будут открываться здесь": @"github.com links from Safari and other apps will open here",
            @"Не удалось сохранить настройку — нет доступа на запись к файлу настроек.": @"Couldn't save the setting — no write access to the preferences file.",

            @"Проверить обновления": @"Check for Updates",
            @"Обновления": @"Updates",
            @"Не удалось проверить обновления. Попробуйте позже.": @"Couldn't check for updates. Try again later.",
            @"Установлена последняя версия.": @"You're on the latest version.",
            @"Доступно обновление": @"Update Available",
            @"Доступна версия %@. Текущая — %@.": @"Version %@ is available. You have %@.",
            @"Позже": @"Later",
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
