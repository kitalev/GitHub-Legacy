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
            @"1. Отсканируйте QR-код или откройте github.com/login/device на компьютере или другом телефоне\n2. Войдите в аккаунт и введите код\n3. Нажмите «Authorize» — этот экран обновится сам":
                @"1. Scan the QR code or open github.com/login/device on a computer or another phone\n2. Sign in and enter the code\n3. Tap \"Authorize\" — this screen will update on its own",
            @"Отсканируйте камерой другого устройства, чтобы открыть github.com/login/device":
                @"Scan with another device's camera to open github.com/login/device",
            @"Войти через Google": @"Sign in with Google",
            @"Вход через Google": @"Sign in with Google",
            @"Вход через аккаунт Google, привязанный к GitHub. Всё происходит прямо в приложении.":
                @"Use the Google account linked to your GitHub. Everything happens right in the app.",
            @"Переход к Google…": @"Opening Google…",
            @"Вход через Google…": @"Signing in with Google…",
            @"Не удалось войти через Google": @"Couldn't sign in with Google",
            @"Проверьте, что аккаунт Google привязан к GitHub, и попробуйте ещё раз.":
                @"Make sure your Google account is linked to GitHub, then try again.",
            @"Email или телефон": @"Email or phone",
            @"Google не ответил.": @"Google didn't respond.",
            @"Далее": @"Next",
            @"Открыть github.com здесь": @"Open github.com here",
            @"Не удалось открыть github.com": @"Couldn't open github.com",
            @"Ожидание подтверждения…": @"Waiting for confirmation…",
            @"Код истёк. Получите новый.": @"The code expired. Get a new one.",
            @"Код действует ещё %ld:%02ld": @"Code expires in %ld:%02ld",
            @"Вход выполнен": @"You're signed in",
            @"Вы вошли как @%@.\nЭто устройство подключено к вашему аккаунту GitHub.": @"Signed in as @%@.\nThis device is now connected to your GitHub account.",
            @"Готово": @"Done",
            @"Вход в GitHub": @"Sign in to GitHub",
            @"Выберите, как войти в аккаунт": @"Choose how you'd like to sign in",
            @"Рекомендуется": @"Recommended",
            @"Другие способы": @"Other options",
            @"Войти в приложении": @"Sign in in the app",
            @"Код из SMS": @"SMS code",
            @"Код восстановления": @"Recovery code",
            @"Код на почту": @"Email code",
            @"GitHub не отправил письмо с кодом (HTTP %ld).": @"GitHub didn't send the email with the code (HTTP %ld).",
            @"Вход в приложении": @"Sign in in the app",
            @"Логин и пароль вводятся прямо в приложении. Вход подтверждается через GitHub Mobile, кодом из приложения-аутентификатора или кодом восстановления.":
                @"Enter your username and password right in the app. Confirm the sign-in with GitHub Mobile, an authenticator app code or a recovery code.",
            @"Продолжить вход": @"Continue signing in",
            @"Отправить запрос ещё раз": @"Send the request again",
            @"Время на подтверждение истекло.": @"The approval request expired.",
            @"Запрос на вход отклонён в GitHub Mobile.": @"The sign-in request was rejected in GitHub Mobile.",
            @"Подключение к github.com…": @"Connecting to github.com…",
            @"Имя пользователя или email": @"Username or email",
            @"Пароль": @"Password",
            @"Подтвердите пароль": @"Confirm your password",
            @"GitHub просит ещё раз ввести пароль, чтобы подтвердить доступ.": @"GitHub asks for your password again to confirm access.",
            @"Подтвердить": @"Confirm",
            @"Код устройства не принят": @"Device code not accepted",
            @"Код %@ не подошёл. Вернитесь назад и получите новый код или попробуйте ещё раз.":
                @"The code %@ wasn't accepted. Go back to get a new code, or try again.",
            @"Попробовать ещё раз": @"Try again",
            @"Разрешить доступ": @"Allow access",
            @"Разрешить": @"Allow",
            @"Двухфакторная проверка": @"Two-factor authentication",
            @"Введите код подтверждения.": @"Enter the verification code.",
            @"Введите код из письма, которое отправил GitHub.": @"Enter the code from the email GitHub sent you.",
            @"Показать": @"Show",
            @"Устройство подтверждено. Завершаем вход…": @"Device approved. Finishing sign-in…",
            @"Завершаем вход…": @"Finishing sign-in…",
            @"Подтверждаем устройство…": @"Approving the device…",
            @"Вход…": @"Signing in…",
            @"Проверка пароля…": @"Checking password…",
            @"Проверка кода…": @"Checking code…",
            @"Шаг %ld из %ld": @"Step %ld of %ld",
            @"Подтвердите вход": @"Confirm sign-in",
            @"Вход не подтверждён": @"Sign-in not approved",
            @"Войдите в аккаунт, чтобы подключить его к приложению.": @"Sign in to connect your account to the app.",
            @"Пароль передаётся только на github.com и не сохраняется в приложении.":
                @"Your password is sent only to github.com and is never stored in the app.",
            @"Выберите, как подтвердить, что это вы.": @"Choose how to confirm it's you.",
            @"Приложение-аутентификатор": @"Authenticator app",
            @"Шестизначный код из Google Authenticator, 1Password и т. п.": @"A six-digit code from Google Authenticator, 1Password and similar apps",
            @"Код придёт на привязанный номер телефона": @"A code is sent to your linked phone number",
            @"GitHub отправит код на почту аккаунта": @"GitHub emails a code to your account address",
            @"Одноразовый код из сохранённого списка": @"A one-time code from your saved list",
            @"Пароль от аккаунта GitHub": @"Your GitHub account password",
            @"Откройте приложение-аутентификатор и введите шестизначный код для GitHub.":
                @"Open your authenticator app and enter the six-digit code for GitHub.",
            @"Введите код из SMS, которое отправил GitHub.": @"Enter the code from the text message GitHub sent you.",
            @"Введите один из сохранённых кодов восстановления. Каждый код работает только один раз.":
                @"Enter one of your saved recovery codes. Each code works only once.",
            @"Откройте GitHub Mobile на телефоне, введите это число и нажмите «Approve».":
                @"Open GitHub Mobile on your phone, enter this number and tap \"Approve\".",
            @"Откройте GitHub Mobile на телефоне и подтвердите запрос на вход.": @"Open GitHub Mobile on your phone and approve the sign-in request.",
            @"Ожидаем подтверждения…": @"Waiting for approval…",
            @"Число нужно, чтобы убедиться, что входите именно вы.": @"The number makes sure it's really you signing in.",
            @"Подтвердите, что это устройство можно подключить к вашему аккаунту GitHub.":
                @"Confirm that this device can be connected to your GitHub account.",
            @"Приложение сможет": @"The app will be able to",
            @"Чтение и запись, включая приватные": @"Read and write, including private ones",
            @"Подписки на пользователей": @"Following users",
            @"Подписываться на людей и отписываться": @"Follow and unfollow people",
            @"Доступ можно отозвать на github.com в Settings → Applications.": @"You can revoke access on github.com in Settings → Applications.",
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
            @"Файл пустой.": @"The file is empty.",
            @"Приложение работает от пользователя mobile и не может прочитать «%@»: файл доступен только root.\n\nОткройте эту папку в файловом менеджере, выберите в ней файл, нажмите «Открыть в…» и выберите GitHub Legacy. Файл сразу прикрепится к задаче.":
                @"The app runs as the mobile user and can't read \"%@\": only root can access this file.\n\nOpen this folder in a file manager, select the file, tap \"Open In…\" and choose GitHub Legacy. The file will be attached to the issue right away.",
            @"Файл получен": @"File received",
            @"«%@» будет прикреплён, когда вы откроете форму новой задачи.": @"\"%@\" will be attached when you open the new issue form.",
            @"Дождитесь окончания текущей загрузки и прикрепите файл ещё раз.": @"Wait for the current upload to finish, then attach the file again.",
            @"Открыть в %@": @"Open in %@",
            @"Открыть %@": @"Open %@",
            @"Выбрать в %@": @"Choose in %@",
            @"Выбор файла": @"Choose a file",
            @"Файл из другого приложения…": @"File from another app…",
            @"Выберите файл и нажмите «Открыть в…» → GitHub Legacy": @"Select a file and tap \"Open In…\" → GitHub Legacy",
            @"В %@ выберите файл, нажмите «Открыть в…» и выберите GitHub Legacy. Файл сразу прикрепится к этой задаче.":
                @"In %@, select the file, tap \"Open In…\" and choose GitHub Legacy. The file will be attached to this issue right away.",
            @"Откройте файл в другом приложении (Почта, Safari, файловый менеджер), нажмите «Открыть в…» и выберите GitHub Legacy. Файл сразу прикрепится к этой задаче.":
                @"Open the file in another app (Mail, Safari, a file manager), tap \"Open In…\" and choose GitHub Legacy. The file will be attached to this issue right away.",
            @"Войдите на github.com, чтобы прикреплять фото и видео.": @"Sign in to github.com to attach photos and videos.",
            @"github.com не разрешил загрузку файлов в этот репозиторий (HTTP %ld).": @"github.com didn't allow uploading files to this repository (HTTP %ld).",
            @"Не удалось загрузить файл в хранилище GitHub (HTTP %ld).": @"Couldn't upload the file to GitHub storage (HTTP %ld).",
            @"github.com не подтвердил загруженный файл (HTTP %ld).": @"github.com didn't confirm the uploaded file (HTTP %ld).",
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
