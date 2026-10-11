#import "GHFileBrowserViewController.h"
#import "GHThemeManager.h"
#import "GHLocalization.h"

static NSString * const kFileBrowserCellID = @"FileBrowserCell";

@interface GHFileBrowserEntry : NSObject
@property (nonatomic, copy) NSString *title;
@property (nonatomic, copy) NSString *path;
@property (nonatomic, assign) BOOL isDirectory;
@property (nonatomic, assign) unsigned long long size;
@end

@implementation GHFileBrowserEntry
@end

@interface GHFileBrowserViewController ()
@property (nonatomic, copy) NSString *path;
@property (nonatomic, strong) NSArray *entries;
@property (nonatomic, copy) NSString *emptyMessage;
@end

@implementation GHFileBrowserViewController

- (id)initWithPath:(NSString *)path {
    self = [super initWithStyle:UITableViewStylePlain];
    if (self) {
        _path = [path copy];
        self.title = path.length > 0 ? ([path isEqualToString:@"/"] ? @"/" : path.lastPathComponent) : GHL(@"Выберите файл");
    }
    return self;
}

- (id)init {
    return [self initWithPath:nil];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.tableView.backgroundColor = GHBackgroundColor();
    self.tableView.backgroundView = nil;
    self.tableView.separatorColor = GHSeparatorColor();
    self.tableView.tableFooterView = [[UIView alloc] initWithFrame:CGRectZero];
    [self loadEntries];
}

+ (NSString *)sizeStringForBytes:(unsigned long long)bytes {
    if (bytes < 1024) return [NSString stringWithFormat:@"%llu %@", bytes, GHL(@"байт")];
    if (bytes < 1024 * 1024) return [NSString stringWithFormat:@"%.1f %@", bytes / 1024.0, GHL(@"КБ")];
    return [NSString stringWithFormat:@"%.1f %@", bytes / (1024.0 * 1024.0), GHL(@"МБ")];
}

- (void)loadEntries {
    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSMutableArray *entries = [NSMutableArray array];

    if (self.path.length == 0) {
        NSArray *places = @[@[GHL(@"Загрузки"), @"/var/mobile/Media/Downloads"],
                            @[GHL(@"Загрузки приложения"), [NSHomeDirectory() stringByAppendingPathComponent:@"Downloads"]],
                            @[GHL(@"Медиа"), @"/var/mobile/Media"],
                            @[GHL(@"Документы"), @"/var/mobile/Documents"],
                            @[GHL(@"Системные логи"), @"/var/log"],
                            @[GHL(@"Корень файловой системы"), @"/"]];
        for (NSArray *place in places) {
            BOOL isDirectory = NO;
            if (![fileManager fileExistsAtPath:place[1] isDirectory:&isDirectory] || !isDirectory) continue;
            GHFileBrowserEntry *entry = [[GHFileBrowserEntry alloc] init];
            entry.title = place[0];
            entry.path = place[1];
            entry.isDirectory = YES;
            [entries addObject:entry];
        }
        self.entries = entries;
        return;
    }

    NSError *error = nil;
    NSArray *names = [fileManager contentsOfDirectoryAtPath:self.path error:&error];
    if (names == nil) {
        self.entries = @[];
        self.emptyMessage = GHL(@"Нет доступа к папке");
        return;
    }

    for (NSString *name in names) {
        NSString *fullPath = [self.path stringByAppendingPathComponent:name];
        BOOL isDirectory = NO;
        if (![fileManager fileExistsAtPath:fullPath isDirectory:&isDirectory]) continue;

        GHFileBrowserEntry *entry = [[GHFileBrowserEntry alloc] init];
        entry.title = name;
        entry.path = fullPath;
        entry.isDirectory = isDirectory;
        if (!isDirectory) entry.size = [[fileManager attributesOfItemAtPath:fullPath error:nil] fileSize];
        [entries addObject:entry];
    }

    [entries sortUsingComparator:^NSComparisonResult(GHFileBrowserEntry *a, GHFileBrowserEntry *b) {
        if (a.isDirectory != b.isDirectory) return a.isDirectory ? NSOrderedAscending : NSOrderedDescending;
        return [a.title localizedCaseInsensitiveCompare:b.title];
    }];
    self.entries = entries;
    self.emptyMessage = GHL(@"Папка пуста");
}

#pragma mark - UITableViewDataSource

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return MAX(self.entries.count, (NSUInteger)1);
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:kFileBrowserCellID];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:kFileBrowserCellID];
    }
    cell.backgroundColor = GHCellBackgroundColor();
    cell.textLabel.backgroundColor = [UIColor clearColor];
    cell.detailTextLabel.backgroundColor = [UIColor clearColor];
    cell.textLabel.font = [UIFont systemFontOfSize:16];
    cell.detailTextLabel.textColor = GHSecondaryTextColor();

    if (self.entries.count == 0) {
        cell.textLabel.text = self.emptyMessage;
        cell.textLabel.textColor = GHSecondaryTextColor();
        cell.detailTextLabel.text = nil;
        cell.accessoryView = nil;
        cell.accessoryType = UITableViewCellAccessoryNone;
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        return cell;
    }

    GHFileBrowserEntry *entry = self.entries[indexPath.row];
    cell.selectionStyle = UITableViewCellSelectionStyleBlue;
    cell.textLabel.textColor = GHPrimaryTextColor();
    cell.textLabel.text = entry.isDirectory && self.path.length > 0 ? [entry.title stringByAppendingString:@"/"] : entry.title;
    if (entry.isDirectory) {
        cell.detailTextLabel.text = self.path.length == 0 ? entry.path : nil;
        GHApplyDisclosureIndicator(cell);
    } else {
        cell.detailTextLabel.text = [GHFileBrowserViewController sizeStringForBytes:entry.size];
        cell.accessoryView = nil;
        cell.accessoryType = UITableViewCellAccessoryNone;
    }
    return cell;
}

#pragma mark - UITableViewDelegate

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (self.entries.count == 0) return;

    GHFileBrowserEntry *entry = self.entries[indexPath.row];
    if (entry.isDirectory) {
        GHFileBrowserViewController *childVC = [[GHFileBrowserViewController alloc] initWithPath:entry.path];
        if (self.path.length == 0) childVC.title = entry.title;
        childVC.onFilePicked = self.onFilePicked;
        [self.navigationController pushViewController:childVC animated:YES];
        return;
    }

    if (self.onFilePicked) self.onFilePicked(entry.path);
}

@end
