#import "LanguageViewController.h"
#import "GHThemeManager.h"
#import "GHLocalization.h"

static NSString * const kLanguageCellID = @"LanguageCell";

@implementation LanguageViewController

- (id)init {
    self = [super initWithStyle:UITableViewStyleGrouped];
    if (self) {
        self.title = GHL(@"Язык");
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                              selector:@selector(applyTheme)
                                                  name:kGHThemeDidChangeNotification
                                                object:nil];
    [self applyTheme];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)applyTheme {
    self.tableView.backgroundColor = GHBackgroundColor();
    self.tableView.backgroundView = nil;
    self.tableView.separatorColor = GHSeparatorColor();
    [self.tableView reloadData];
}

#pragma mark - UITableViewDataSource

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return 2;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:kLanguageCellID];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:kLanguageCellID];
    }
    cell.backgroundColor = GHCellBackgroundColor();
    cell.selectionStyle = UITableViewCellSelectionStyleBlue;

    NSString *code = (indexPath.row == 0) ? @"ru" : @"en";
    cell.textLabel.text = (indexPath.row == 0) ? GHL(@"Русский") : GHL(@"Английский");
    cell.textLabel.textColor = GHPrimaryTextColor();

    BOOL isCurrent = [[GHLocalization sharedManager].languageCode isEqualToString:code];
    cell.accessoryType = isCurrent ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;

    return cell;
}

#pragma mark - UITableViewDelegate

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    NSString *code = (indexPath.row == 0) ? @"ru" : @"en";
    [GHLocalization sharedManager].languageCode = code;

    [self.navigationController popViewControllerAnimated:YES];
}

@end
