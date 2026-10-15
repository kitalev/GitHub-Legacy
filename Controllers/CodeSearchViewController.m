#import "CodeSearchViewController.h"
#import "GHAPIClient.h"
#import "GHAuthManager.h"
#import "GHThemeManager.h"
#import "GHLocalization.h"
#import "ReadmeViewController.h"

static NSString * const kCodeSearchResultCellID = @"CodeSearchResultCell";
static NSString * const kCodeSearchMessageCellID = @"CodeSearchMessageCell";
static const CGFloat kCodeSearchSnippetFontSize = 12;

@interface CodeSearchViewController ()
@property (nonatomic, strong) UISearchBar *searchBar;
@property (nonatomic, strong) NSArray *results;
@property (nonatomic, copy) NSString *query;
@property (nonatomic, copy) NSString *errorMessage;
@property (nonatomic, assign) BOOL loading;
@property (nonatomic, assign) BOOL searched;
@property (nonatomic, assign) NSInteger totalCount;
@property (nonatomic, strong) UIActivityIndicatorView *spinner;
@end

@implementation CodeSearchViewController

- (id)init {
    self = [super initWithStyle:UITableViewStylePlain];
    if (self) {
        self.title = GHL(@"Поиск по коду");
        _results = @[];
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];

    self.searchBar = [[UISearchBar alloc] initWithFrame:CGRectMake(0, 0, self.view.bounds.size.width, 44)];
    self.searchBar.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    self.searchBar.placeholder = GHL(@"Текст, функция или имя файла");
    self.searchBar.autocapitalizationType = UITextAutocapitalizationTypeNone;
    self.searchBar.autocorrectionType = UITextAutocorrectionTypeNo;
    self.searchBar.delegate = self;
    self.tableView.tableHeaderView = self.searchBar;

    self.spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleGray];
    self.spinner.hidesWhenStopped = YES;
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithCustomView:self.spinner];

    [[NSNotificationCenter defaultCenter] addObserver:self
                                              selector:@selector(applyTheme)
                                                  name:kGHThemeDidChangeNotification
                                                object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                              selector:@selector(handleLanguageDidChange)
                                                  name:kGHLanguageDidChangeNotification
                                                object:nil];
    [self applyTheme];
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    if (!self.searched && self.searchBar.text.length == 0) [self.searchBar becomeFirstResponder];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)handleLanguageDidChange {
    self.title = GHL(@"Поиск по коду");
    self.searchBar.placeholder = GHL(@"Текст, функция или имя файла");
    [self.tableView reloadData];
}

- (void)applyTheme {
    BOOL dark = [GHThemeManager sharedManager].darkModeEnabled;
    self.tableView.backgroundColor = GHBackgroundColor();
    self.tableView.backgroundView = nil;
    self.tableView.separatorColor = GHSeparatorColor();
    self.spinner.activityIndicatorViewStyle = GHSpinnerStyle();
    self.searchBar.barStyle = dark ? UIBarStyleBlack : UIBarStyleDefault;
    self.searchBar.tintColor = GHTintColor();
    [self.tableView reloadData];
}

#pragma mark - Search

- (void)searchBarSearchButtonClicked:(UISearchBar *)searchBar {
    [searchBar resignFirstResponder];
    [self performSearch];
}

- (void)performSearch {
    NSString *text = [self.searchBar.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (text.length == 0) return;
    self.query = text;
    self.searched = YES;
    self.errorMessage = nil;

    if (![GHAuthManager sharedManager].isAuthenticated) {
        self.results = @[];
        self.errorMessage = GHL(@"GitHub ищет по коду только для вошедших пользователей. Войдите в аккаунт в настройках.");
        [self.tableView reloadData];
        return;
    }

    self.loading = YES;
    [self.spinner startAnimating];
    [self.tableView reloadData];

    NSString *scoped = [NSString stringWithFormat:@"%@ repo:%@/%@", text, self.ownerLogin, self.repoName];
    __weak typeof(self) weakSelf = self;
    [[GHAPIClient sharedClient] searchCodeWithQuery:scoped completion:^(id jsonObject, NSError *error) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf || ![strongSelf.query isEqualToString:text]) return;
        strongSelf.loading = NO;
        [strongSelf.spinner stopAnimating];
        NSDictionary *root = [jsonObject isKindOfClass:[NSDictionary class]] ? jsonObject : nil;
        NSArray *items = [root[@"items"] isKindOfClass:[NSArray class]] ? root[@"items"] : nil;
        if (error || items == nil) {
            strongSelf.results = @[];
            strongSelf.errorMessage = error.localizedDescription ?: GHL(@"неизвестная ошибка");
        } else {
            strongSelf.results = items;
            strongSelf.totalCount = [root[@"total_count"] respondsToSelector:@selector(integerValue)] ? [root[@"total_count"] integerValue] : items.count;
        }
        [strongSelf.tableView reloadData];
    }];
}

#pragma mark - Result helpers

- (NSString *)stringForKey:(NSString *)key inItem:(NSDictionary *)item {
    id value = item[key];
    return [value isKindOfClass:[NSString class]] ? value : @"";
}

- (NSString *)snippetForItem:(NSDictionary *)item {
    NSArray *matches = [item[@"text_matches"] isKindOfClass:[NSArray class]] ? item[@"text_matches"] : nil;
    for (NSDictionary *match in matches) {
        if (![match isKindOfClass:[NSDictionary class]]) continue;
        if (![[self stringForKey:@"property" inItem:match] isEqualToString:@"content"]) continue;
        NSString *fragment = [self stringForKey:@"fragment" inItem:match];
        if (fragment.length == 0) continue;
        NSMutableArray *lines = [NSMutableArray array];
        NSString *needle = [self.query lowercaseString];
        for (NSString *line in [fragment componentsSeparatedByString:@"\n"]) {
            NSString *trimmed = [line stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
            if (trimmed.length == 0) continue;
            if ([[trimmed lowercaseString] rangeOfString:needle].location != NSNotFound) [lines insertObject:trimmed atIndex:0];
            else [lines addObject:trimmed];
        }
        NSArray *shown = [lines subarrayWithRange:NSMakeRange(0, MIN((NSUInteger)2, lines.count))];
        return [shown componentsJoinedByString:@"\n"];
    }
    return @"";
}

- (UIFont *)snippetFont {
    return [UIFont fontWithName:@"Menlo-Regular" size:kCodeSearchSnippetFontSize]
        ?: [UIFont fontWithName:@"Courier" size:kCodeSearchSnippetFontSize + 1]
        ?: [UIFont systemFontOfSize:kCodeSearchSnippetFontSize];
}

- (NSString *)messageText {
    if (self.errorMessage.length > 0) return self.errorMessage;
    if (self.loading) return GHL(@"Поиск…");
    if (self.searched) return GHL(@"Ничего не найдено");
    return GHL(@"Введите текст и нажмите «Найти». Ищется по основной ветке репозитория.");
}

- (BOOL)showsMessage {
    return self.results.count == 0 || self.loading;
}

#pragma mark - UITableViewDataSource

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return [self showsMessage] ? 1 : self.results.count;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    if ([self showsMessage]) return nil;
    return [NSString stringWithFormat:GHL(@"Найдено файлов: %ld"), (long)MAX(self.totalCount, (NSInteger)self.results.count)];
}

- (UIView *)tableView:(UITableView *)tableView viewForHeaderInSection:(NSInteger)section {
    return GHThemedSectionHeaderView([self tableView:tableView titleForHeaderInSection:section]);
}

- (CGFloat)tableView:(UITableView *)tableView heightForHeaderInSection:(NSInteger)section {
    return GHThemedSectionHeaderHeight([self tableView:tableView titleForHeaderInSection:section]);
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    CGFloat width = tableView.bounds.size.width - 40;
    if ([self showsMessage]) {
        CGSize size = [[self messageText] sizeWithFont:[UIFont systemFontOfSize:15]
                                     constrainedToSize:CGSizeMake(width, CGFLOAT_MAX)
                                         lineBreakMode:NSLineBreakByWordWrapping];
        return MAX(44, ceil(size.height) + 24);
    }
    NSString *snippet = [self snippetForItem:self.results[indexPath.row]];
    CGFloat snippetHeight = 0;
    if (snippet.length > 0) {
        CGSize size = [snippet sizeWithFont:[self snippetFont]
                          constrainedToSize:CGSizeMake(width, [self snippetFont].lineHeight * 2 + 2)
                              lineBreakMode:NSLineBreakByTruncatingTail];
        snippetHeight = ceil(size.height) + 6;
    }
    return 10 + 20 + 16 + snippetHeight + 10;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    if ([self showsMessage]) {
        UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:kCodeSearchMessageCellID];
        if (!cell) cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:kCodeSearchMessageCellID];
        cell.backgroundColor = GHCellBackgroundColor();
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        cell.textLabel.backgroundColor = [UIColor clearColor];
        cell.textLabel.numberOfLines = 0;
        cell.textLabel.font = [UIFont systemFontOfSize:15];
        cell.textLabel.textColor = self.errorMessage.length > 0 ? [UIColor colorWithRed:0.84 green:0.23 blue:0.23 alpha:1.0] : GHSecondaryTextColor();
        cell.textLabel.text = [self messageText];
        return cell;
    }

    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:kCodeSearchResultCellID];
    UILabel *nameLabel = nil;
    UILabel *pathLabel = nil;
    UILabel *snippetLabel = nil;
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:kCodeSearchResultCellID];
        for (NSInteger tag = 1001; tag <= 1003; tag++) {
            UILabel *label = [[UILabel alloc] init];
            label.backgroundColor = [UIColor clearColor];
            label.tag = tag;
            label.autoresizingMask = UIViewAutoresizingFlexibleWidth;
            [cell.contentView addSubview:label];
        }
    }
    nameLabel = (UILabel *)[cell.contentView viewWithTag:1001];
    pathLabel = (UILabel *)[cell.contentView viewWithTag:1002];
    snippetLabel = (UILabel *)[cell.contentView viewWithTag:1003];

    NSDictionary *item = self.results[indexPath.row];
    NSString *path = [self stringForKey:@"path" inItem:item];
    NSString *directory = [path stringByDeletingLastPathComponent];
    NSString *snippet = [self snippetForItem:item];
    CGFloat width = tableView.bounds.size.width - 40;

    cell.backgroundColor = GHCellBackgroundColor();
    GHApplyDisclosureIndicator(cell);

    nameLabel.font = [UIFont boldSystemFontOfSize:16];
    nameLabel.textColor = GHPrimaryTextColor();
    nameLabel.text = [self stringForKey:@"name" inItem:item];
    nameLabel.frame = CGRectMake(15, 10, width, 20);

    pathLabel.font = [UIFont systemFontOfSize:13];
    pathLabel.textColor = GHSecondaryTextColor();
    pathLabel.lineBreakMode = NSLineBreakByTruncatingHead;
    pathLabel.text = directory.length > 0 ? [directory stringByAppendingString:@"/"] : @"/";
    pathLabel.frame = CGRectMake(15, 30, width, 16);

    snippetLabel.font = [self snippetFont];
    snippetLabel.textColor = GHPrimaryTextColor();
    snippetLabel.numberOfLines = 2;
    snippetLabel.lineBreakMode = NSLineBreakByTruncatingTail;
    snippetLabel.text = snippet;
    CGFloat snippetHeight = snippet.length > 0 ? ceil([snippet sizeWithFont:snippetLabel.font
                                                            constrainedToSize:CGSizeMake(width, snippetLabel.font.lineHeight * 2 + 2)
                                                                lineBreakMode:NSLineBreakByTruncatingTail].height) : 0;
    snippetLabel.frame = CGRectMake(15, 52, width, snippetHeight);
    snippetLabel.hidden = snippet.length == 0;
    return cell;
}

#pragma mark - UITableViewDelegate

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if ([self showsMessage]) return;
    NSDictionary *item = self.results[indexPath.row];
    NSString *path = [self stringForKey:@"path" inItem:item];
    if (path.length == 0) return;
    NSString *htmlURL = [self stringForKey:@"html_url" inItem:item];
    [ReadmeViewController openRepoFileAtPath:path
                                  ownerLogin:self.ownerLogin
                                    repoName:self.repoName
                          fromViewController:self
                                 fallbackURL:htmlURL.length > 0 ? [NSURL URLWithString:htmlURL] : nil];
}

- (void)scrollViewWillBeginDragging:(UIScrollView *)scrollView {
    [self.searchBar resignFirstResponder];
}

@end
