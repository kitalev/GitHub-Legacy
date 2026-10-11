#import "IssueTemplatePickerViewController.h"
#import "NewIssueViewController.h"
#import "GHIssueTemplate.h"
#import "GHThemeManager.h"
#import "GHLocalization.h"
#import "GHIconRenderer.h"
#import "GHCompat.h"
#import "GHURLRouter.h"

static NSString * const kTemplateChoiceCellID = @"TemplateChoiceCell";
static const CGFloat kChoiceHorizontalMargin = 16;
static const CGFloat kChoiceVerticalMargin = 14;
static const CGFloat kChoiceAccessoryAllowance = 44;
static const CGFloat kChoiceTitleFontSize = 18;
static const CGFloat kChoiceSubtitleFontSize = 15;

@interface GHIssueTemplateChoiceCell : UITableViewCell
@property (nonatomic, strong) UILabel *choiceTitleLabel;
@property (nonatomic, strong) UILabel *choiceSubtitleLabel;
+ (CGFloat)heightForTitle:(NSString *)title subtitle:(NSString *)subtitle width:(CGFloat)width;
@end

@implementation GHIssueTemplateChoiceCell

- (id)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
    if (self) {
        _choiceTitleLabel = [[UILabel alloc] init];
        _choiceTitleLabel.backgroundColor = [UIColor clearColor];
        _choiceTitleLabel.font = [UIFont systemFontOfSize:kChoiceTitleFontSize];
        _choiceTitleLabel.numberOfLines = 0;
        [self.contentView addSubview:_choiceTitleLabel];

        _choiceSubtitleLabel = [[UILabel alloc] init];
        _choiceSubtitleLabel.backgroundColor = [UIColor clearColor];
        _choiceSubtitleLabel.font = [UIFont systemFontOfSize:kChoiceSubtitleFontSize];
        _choiceSubtitleLabel.numberOfLines = 0;
        [self.contentView addSubview:_choiceSubtitleLabel];
    }
    return self;
}

+ (CGFloat)textHeight:(NSString *)text fontSize:(CGFloat)fontSize width:(CGFloat)width {
    if (text.length == 0) return 0;
    CGSize size = [text sizeWithFont:[UIFont systemFontOfSize:fontSize]
                   constrainedToSize:CGSizeMake(width, CGFLOAT_MAX)
                       lineBreakMode:NSLineBreakByWordWrapping];
    return ceil(size.height);
}

+ (CGFloat)heightForTitle:(NSString *)title subtitle:(NSString *)subtitle width:(CGFloat)width {
    CGFloat textWidth = width - kChoiceHorizontalMargin - kChoiceAccessoryAllowance;
    CGFloat height = kChoiceVerticalMargin * 2 + [self textHeight:title fontSize:kChoiceTitleFontSize width:textWidth];
    if (subtitle.length > 0) height += 3 + [self textHeight:subtitle fontSize:kChoiceSubtitleFontSize width:textWidth];
    return MAX(height, 56);
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat width = self.contentView.bounds.size.width - kChoiceHorizontalMargin - 4;
    CGFloat titleHeight = [GHIssueTemplateChoiceCell textHeight:self.choiceTitleLabel.text fontSize:kChoiceTitleFontSize width:width];
    CGFloat subtitleHeight = [GHIssueTemplateChoiceCell textHeight:self.choiceSubtitleLabel.text fontSize:kChoiceSubtitleFontSize width:width];
    CGFloat total = titleHeight + (subtitleHeight > 0 ? 3 + subtitleHeight : 0);
    CGFloat y = floor((self.contentView.bounds.size.height - total) / 2.0);
    self.choiceTitleLabel.frame = CGRectMake(kChoiceHorizontalMargin, y, width, titleHeight);
    self.choiceSubtitleLabel.frame = CGRectMake(kChoiceHorizontalMargin, y + titleHeight + 3, width, subtitleHeight);
}

@end

@interface IssueTemplatePickerViewController ()
@property (nonatomic, strong) NSArray *sections;
@property (nonatomic, strong) UILabel *repoLabel;
@property (nonatomic, strong) UILabel *headingLabel;
@end

@implementation IssueTemplatePickerViewController

- (id)init {
    self = [super initWithStyle:UITableViewStylePlain];
    if (self) {
        self.title = GHL(@"Новая задача");
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];

    NSMutableArray *sections = [NSMutableArray array];
    if (self.templateSet.contactLinks.count > 0) [sections addObject:self.templateSet.contactLinks];
    NSMutableArray *templateRows = [NSMutableArray arrayWithArray:self.templateSet.templates ?: @[]];
    if (self.templateSet.blankIssuesEnabled || templateRows.count == 0) [templateRows addObject:[NSNull null]];
    [sections addObject:templateRows];
    self.sections = sections;

    UIView *header = [[UIView alloc] initWithFrame:CGRectMake(0, 0, self.view.bounds.size.width, 78)];
    header.autoresizingMask = UIViewAutoresizingFlexibleWidth;

    self.repoLabel = [[UILabel alloc] initWithFrame:CGRectMake(kChoiceHorizontalMargin, 12, header.bounds.size.width - 32, 20)];
    self.repoLabel.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    self.repoLabel.backgroundColor = [UIColor clearColor];
    self.repoLabel.font = [UIFont systemFontOfSize:15];
    self.repoLabel.text = [NSString stringWithFormat:@"%@/%@", self.ownerLogin, self.repoName];
    [header addSubview:self.repoLabel];

    self.headingLabel = [[UILabel alloc] initWithFrame:CGRectMake(kChoiceHorizontalMargin, 34, header.bounds.size.width - 32, 32)];
    self.headingLabel.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    self.headingLabel.backgroundColor = [UIColor clearColor];
    self.headingLabel.font = [UIFont boldSystemFontOfSize:26];
    self.headingLabel.adjustsFontSizeToFitWidth = YES;
    self.headingLabel.text = GHL(@"Выберите шаблон");
    [header addSubview:self.headingLabel];

    self.tableView.tableHeaderView = header;
    self.tableView.tableFooterView = [[UIView alloc] initWithFrame:CGRectZero];

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
    self.tableView.tableHeaderView.backgroundColor = GHBackgroundColor();
    self.repoLabel.textColor = GHSecondaryTextColor();
    self.headingLabel.textColor = GHPrimaryTextColor();
    [self.tableView reloadData];
}

- (id)itemAtIndexPath:(NSIndexPath *)indexPath {
    return self.sections[indexPath.section][indexPath.row];
}

- (void)getTitle:(NSString **)title subtitle:(NSString **)subtitle forItem:(id)item {
    if ([item isKindOfClass:[GHIssueContactLink class]]) {
        GHIssueContactLink *link = item;
        *title = link.name;
        *subtitle = link.about;
    } else if ([item isKindOfClass:[GHIssueTemplate class]]) {
        GHIssueTemplate *template = item;
        *title = template.name;
        *subtitle = template.about;
    } else {
        *title = GHL(@"Пустая задача");
        *subtitle = GHL(@"Создать задачу без шаблона.");
    }
    *title = GHEmojiForDisplay(*title);
    *subtitle = GHEmojiForDisplay(*subtitle);
}

#pragma mark - UITableViewDataSource

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return self.sections.count;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return [self.sections[section] count];
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    GHIssueTemplateChoiceCell *cell = [tableView dequeueReusableCellWithIdentifier:kTemplateChoiceCellID];
    if (!cell) {
        cell = [[GHIssueTemplateChoiceCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:kTemplateChoiceCellID];
    }
    cell.backgroundColor = GHCellBackgroundColor();
    cell.choiceTitleLabel.textColor = GHPrimaryTextColor();
    cell.choiceSubtitleLabel.textColor = GHSecondaryTextColor();

    id item = [self itemAtIndexPath:indexPath];
    NSString *title = nil;
    NSString *subtitle = nil;
    [self getTitle:&title subtitle:&subtitle forItem:item];
    cell.choiceTitleLabel.text = title;
    cell.choiceSubtitleLabel.text = subtitle;

    if ([item isKindOfClass:[GHIssueContactLink class]]) {
        cell.accessoryType = UITableViewCellAccessoryNone;
        cell.accessoryView = [[UIImageView alloc] initWithImage:[GHIconRenderer externalLinkIconWithColor:GHSecondaryTextColor() size:20]];
    } else {
        GHApplyDisclosureIndicator(cell);
    }
    [cell setNeedsLayout];
    return cell;
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    NSString *title = nil;
    NSString *subtitle = nil;
    [self getTitle:&title subtitle:&subtitle forItem:[self itemAtIndexPath:indexPath]];
    return [GHIssueTemplateChoiceCell heightForTitle:title subtitle:subtitle width:tableView.bounds.size.width];
}

- (CGFloat)tableView:(UITableView *)tableView heightForHeaderInSection:(NSInteger)section {
    return section == 0 ? 0 : 12;
}

- (UIView *)tableView:(UITableView *)tableView viewForHeaderInSection:(NSInteger)section {
    if (section == 0) return nil;
    UIView *spacer = [[UIView alloc] initWithFrame:CGRectMake(0, 0, tableView.bounds.size.width, 12)];
    spacer.backgroundColor = GHBackgroundColor();
    UIView *line = [[UIView alloc] initWithFrame:CGRectMake(0, 0, tableView.bounds.size.width, 1)];
    line.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    line.backgroundColor = GHSeparatorColor();
    [spacer addSubview:line];
    return spacer;
}

#pragma mark - UITableViewDelegate

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    id item = [self itemAtIndexPath:indexPath];

    if ([item isKindOfClass:[GHIssueContactLink class]]) {
        NSURL *url = ((GHIssueContactLink *)item).url;
        if (![GHURLRouter routeGitHubURL:url fromViewController:self]) {
            [[UIApplication sharedApplication] openURL:url];
        }
        return;
    }

    NewIssueViewController *composer = [[NewIssueViewController alloc] init];
    composer.ownerLogin = self.ownerLogin;
    composer.repoName = self.repoName;
    composer.issueTemplate = [item isKindOfClass:[GHIssueTemplate class]] ? item : nil;
    composer.onIssueCreated = self.onIssueCreated;
    [self.navigationController pushViewController:composer animated:YES];
}

@end
