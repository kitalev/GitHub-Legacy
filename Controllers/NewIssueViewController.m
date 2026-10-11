#import "NewIssueViewController.h"
#import <QuartzCore/QuartzCore.h>
#import "IssueDetailViewController.h"
#import "GHFileBrowserViewController.h"
#import "GHAttachmentUploader.h"
#import "GHIssueTemplate.h"
#import "GHAPIClient.h"
#import "GHThemeManager.h"
#import "GHLocalization.h"
#import "GHIconRenderer.h"
#import "GHCompat.h"

static const CGFloat kInputHeight = 44;
static const CGFloat kTextareaHeight = 140;
static const CGFloat kBodyTextareaHeight = 260;
static const NSUInteger kMaxIssueBodyLength = 65536;
static const NSUInteger kMaxInlineFileCharacters = 60000;
static const unsigned long long kMaxFileReadBytes = 256 * 1024;
static const CGFloat kMaxPhotoDimension = 2048;
static const NSInteger kUnreadableFileAlertTag = 1;

static __weak NewIssueViewController *gActiveComposer = nil;
static NSString *gPendingIncomingFilePath = nil;

static UIColor *GHNewIssueErrorColor(void) {
    return [UIColor colorWithRed:0.84 green:0.23 blue:0.23 alpha:1.0];
}

static UILabel *GHNewIssueMakeLabel(UIFont *font) {
    UILabel *label = [[UILabel alloc] init];
    label.backgroundColor = [UIColor clearColor];
    label.font = font;
    label.numberOfLines = 0;
    return label;
}

static CGFloat GHNewIssueLabelHeight(UILabel *label, CGFloat width) {
    if (label.text.length == 0) return 0;
    CGSize size = [label.text sizeWithFont:label.font
                         constrainedToSize:CGSizeMake(width, CGFLOAT_MAX)
                             lineBreakMode:NSLineBreakByWordWrapping];
    return ceil(size.height);
}

static NSString *GHPlainTextFromMarkdown(NSString *markdown) {
    NSString *text = markdown ?: @"";
    NSArray *rules = @[
        @[@"<!--[\\s\\S]*?-->", @""],
        @[@"!\\[([^\\]]*)\\]\\([^)]*\\)", @"$1"],
        @[@"\\[([^\\]]+)\\]\\([^)]*\\)", @"$1"],
        @[@"<br\\s*/?>", @"\n"],
        @[@"</?[a-zA-Z][^>]*>", @""],
        @[@"(?m)^[ \\t]{0,3}#{1,6}[ \\t]*", @""],
        @[@"(?m)^[ \\t]{0,3}>[ \\t]?", @""],
        @[@"(\\*\\*|__)(.+?)\\1", @"$2"],
        @[@"`([^`]+)`", @"$1"],
        @[@"(?m)^[ \\t]*[-*+][ \\t]+", @"• "],
        @[@"\\n{3,}", @"\n\n"]
    ];
    for (NSArray *rule in rules) {
        NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:rule[0] options:0 error:nil];
        text = [regex stringByReplacingMatchesInString:text options:0 range:NSMakeRange(0, text.length) withTemplate:rule[1]];
    }
    return GHEmojiForDisplay([text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]]);
}

#pragma mark - GHPlaceholderTextView

@interface GHPlaceholderTextView : UITextView
@property (nonatomic, strong) UILabel *placeholderLabel;
- (void)updatePlaceholder;
@end

@implementation GHPlaceholderTextView

- (id)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        _placeholderLabel = GHNewIssueMakeLabel([UIFont systemFontOfSize:15]);
        _placeholderLabel.userInteractionEnabled = NO;
        [self addSubview:_placeholderLabel];
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                  selector:@selector(updatePlaceholder)
                                                      name:UITextViewTextDidChangeNotification
                                                    object:self];
    }
    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)setText:(NSString *)text {
    [super setText:text];
    [self updatePlaceholder];
}

- (void)setFont:(UIFont *)font {
    [super setFont:font];
    self.placeholderLabel.font = font;
    [self setNeedsLayout];
}

- (void)updatePlaceholder {
    self.placeholderLabel.hidden = self.text.length > 0 || self.placeholderLabel.text.length == 0;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat x = [self respondsToSelector:@selector(setTextContainerInset:)] ? 5 : 8;
    CGFloat width = self.bounds.size.width - x * 2;
    CGFloat height = MIN(GHNewIssueLabelHeight(self.placeholderLabel, width), self.bounds.size.height - 16);
    self.placeholderLabel.frame = CGRectMake(x, 8, width, MAX(height, 0));
}

@end

#pragma mark - GHIssueOptionsViewController

@interface GHIssueOptionsViewController : UITableViewController
@property (nonatomic, copy) NSArray *options;
@property (nonatomic, assign) BOOL multiple;
@property (nonatomic, assign) BOOL allowsNone;
@property (nonatomic, strong) NSMutableIndexSet *selection;
@property (nonatomic, copy) void (^onChange)(void);
@end

@implementation GHIssueOptionsViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.tableView.backgroundColor = GHBackgroundColor();
    self.tableView.backgroundView = nil;
    self.tableView.separatorColor = GHSeparatorColor();
    self.tableView.tableFooterView = [[UIView alloc] initWithFrame:CGRectZero];
}

- (NSInteger)noneOffset {
    return (self.allowsNone && !self.multiple) ? 1 : 0;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return self.options.count + [self noneOffset];
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"OptionCell"];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"OptionCell"];
    }
    cell.backgroundColor = GHCellBackgroundColor();
    cell.textLabel.backgroundColor = [UIColor clearColor];
    cell.textLabel.numberOfLines = 0;
    cell.textLabel.font = [UIFont systemFontOfSize:16];

    NSInteger optionIndex = indexPath.row - [self noneOffset];
    BOOL selected;
    if (optionIndex < 0) {
        cell.textLabel.text = GHL(@"Нет");
        cell.textLabel.textColor = GHSecondaryTextColor();
        selected = self.selection.count == 0;
    } else {
        cell.textLabel.text = GHEmojiForDisplay(self.options[optionIndex]);
        cell.textLabel.textColor = GHPrimaryTextColor();
        selected = [self.selection containsIndex:(NSUInteger)optionIndex];
    }
    cell.accessoryType = selected ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;
    return cell;
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    NSInteger optionIndex = indexPath.row - [self noneOffset];
    if (optionIndex < 0) return 44;
    CGSize size = [self.options[optionIndex] sizeWithFont:[UIFont systemFontOfSize:16]
                                        constrainedToSize:CGSizeMake(tableView.bounds.size.width - 70, CGFLOAT_MAX)
                                            lineBreakMode:NSLineBreakByWordWrapping];
    return MAX(44, ceil(size.height) + 22);
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    NSInteger optionIndex = indexPath.row - [self noneOffset];

    if (self.multiple) {
        if ([self.selection containsIndex:(NSUInteger)optionIndex]) {
            [self.selection removeIndex:(NSUInteger)optionIndex];
        } else {
            [self.selection addIndex:(NSUInteger)optionIndex];
        }
        [tableView reloadData];
        if (self.onChange) self.onChange();
        return;
    }

    [self.selection removeAllIndexes];
    if (optionIndex >= 0) [self.selection addIndex:(NSUInteger)optionIndex];
    [tableView reloadData];
    if (self.onChange) self.onChange();
    [self.navigationController popViewControllerAnimated:YES];
}

@end

#pragma mark - GHIssueFieldRow

@interface GHIssueFieldRow : NSObject
@property (nonatomic, strong) GHIssueFormField *field;
@property (nonatomic, strong) id value;
@property (nonatomic, assign) BOOL isBody;
@property (nonatomic, assign) BOOL invalid;
@property (nonatomic, strong) UILabel *captionLabel;
@property (nonatomic, strong) UILabel *descriptionLabel;
@property (nonatomic, strong) UILabel *markdownLabel;
@property (nonatomic, strong) UIView *card;
@property (nonatomic, strong) UITextField *textField;
@property (nonatomic, strong) GHPlaceholderTextView *textView;
@property (nonatomic, strong) UIButton *dropdownButton;
@property (nonatomic, strong) UILabel *dropdownLabel;
@property (nonatomic, strong) UIImageView *dropdownChevron;
@property (nonatomic, strong) NSArray *checkboxLabels;
@property (nonatomic, strong) NSArray *checkboxSwitches;
@property (nonatomic, strong) NSArray *checkboxSeparators;
@property (nonatomic, strong) UIButton *attachButton;
@end

@implementation GHIssueFieldRow

- (id)currentValue {
    switch (self.field.type) {
        case GHIssueFormFieldTypeInput:
            return self.textField.text ?: @"";
        case GHIssueFormFieldTypeTextarea:
            return self.textView.text ?: @"";
        case GHIssueFormFieldTypeCheckboxes: {
            NSMutableIndexSet *checked = [NSMutableIndexSet indexSet];
            for (NSUInteger i = 0; i < self.checkboxSwitches.count; i++) {
                if ([self.checkboxSwitches[i] isOn]) [checked addIndex:i];
            }
            return checked;
        }
        default:
            return self.value;
    }
}

@end

#pragma mark - NewIssueViewController

@interface NewIssueViewController () <UITextFieldDelegate, UITextViewDelegate, UIActionSheetDelegate,
                                      UIImagePickerControllerDelegate, UINavigationControllerDelegate,
                                      UIAlertViewDelegate>
@property (nonatomic, weak) GHIssueFieldRow *attachTargetRow;
@property (nonatomic, copy) NSArray *fileManagerURLs;
@property (nonatomic, copy) NSArray *attachActions;
@property (nonatomic, strong) UIPopoverController *imagePopover;
@property (nonatomic, strong) GHAttachmentUploader *activeUpload;
@property (nonatomic, assign) long long uploadRepositoryID;
@property (nonatomic, copy) NSString *uploadRepositoryFullName;
@property (nonatomic, strong) UIScrollView *scrollView;
@property (nonatomic, strong) UILabel *repoLabel;
@property (nonatomic, strong) UILabel *templateLabel;
@property (nonatomic, strong) GHIssueFieldRow *titleRow;
@property (nonatomic, strong) NSMutableArray *rows;
@property (nonatomic, strong) UIButton *submitButton;
@property (nonatomic, strong) UIBarButtonItem *submitItem;
@property (nonatomic, strong) UIActivityIndicatorView *spinner;
@property (nonatomic, weak) UIView *activeInputView;
@property (nonatomic, assign) BOOL submitting;
@property (nonatomic, assign) BOOL didAutoFocusTitle;
@end

@implementation NewIssueViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = GHL(@"Новая задача");

    self.scrollView = [[UIScrollView alloc] initWithFrame:self.view.bounds];
    self.scrollView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.scrollView.alwaysBounceVertical = YES;
    [self.view addSubview:self.scrollView];

    UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(dismissKeyboard)];
    tap.cancelsTouchesInView = NO;
    [self.scrollView addGestureRecognizer:tap];

    self.repoLabel = GHNewIssueMakeLabel([UIFont systemFontOfSize:14]);
    self.repoLabel.text = [NSString stringWithFormat:@"%@/%@", self.ownerLogin, self.repoName];
    [self.scrollView addSubview:self.repoLabel];

    self.templateLabel = GHNewIssueMakeLabel([UIFont boldSystemFontOfSize:20]);
    self.templateLabel.text = GHEmojiForDisplay(self.issueTemplate.name.length > 0 ? self.issueTemplate.name : GHL(@"Новая задача"));
    [self.scrollView addSubview:self.templateLabel];

    self.rows = [NSMutableArray array];

    GHIssueFormField *titleField = [[GHIssueFormField alloc] init];
    titleField.type = GHIssueFormFieldTypeInput;
    titleField.label = GHL(@"Заголовок");
    titleField.placeholder = GHL(@"Заголовок");
    titleField.value = self.issueTemplate.title;
    titleField.required = YES;
    self.titleRow = [self buildRowForField:titleField];
    self.titleRow.textField.returnKeyType = UIReturnKeyDone;
    [self.rows addObject:self.titleRow];

    if (self.issueTemplate.isForm) {
        for (GHIssueFormField *field in self.issueTemplate.fields) {
            [self.rows addObject:[self buildRowForField:field]];
        }
    } else {
        GHIssueFormField *bodyField = [[GHIssueFormField alloc] init];
        bodyField.type = GHIssueFormFieldTypeTextarea;
        bodyField.label = GHL(@"Описание");
        bodyField.placeholder = GHL(@"Опишите задачу. Поддерживается Markdown.");
        bodyField.value = self.issueTemplate.body;
        GHIssueFieldRow *bodyRow = [self buildRowForField:bodyField];
        bodyRow.isBody = YES;
        [self.rows addObject:bodyRow];
    }

    self.submitButton = [UIButton buttonWithType:UIButtonTypeRoundedRect];
    [self.submitButton setTitle:GHL(@"Создать задачу") forState:UIControlStateNormal];
    self.submitButton.titleLabel.font = [UIFont boldSystemFontOfSize:17];
    [self.submitButton addTarget:self action:@selector(submitTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.scrollView addSubview:self.submitButton];

    self.submitItem = [[UIBarButtonItem alloc] initWithTitle:GHL(@"Создать")
                                                       style:UIBarButtonItemStyleDone
                                                      target:self
                                                      action:@selector(submitTapped)];
    self.navigationItem.rightBarButtonItem = self.submitItem;

    self.spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleGray];
    self.spinner.hidesWhenStopped = YES;

    [[NSNotificationCenter defaultCenter] addObserver:self
                                              selector:@selector(applyTheme)
                                                  name:kGHThemeDidChangeNotification
                                                object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                              selector:@selector(keyboardWillShow:)
                                                  name:UIKeyboardWillShowNotification
                                                object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                              selector:@selector(keyboardWillHide:)
                                                  name:UIKeyboardWillHideNotification
                                                object:nil];

    [self applyTheme];
}

+ (void)receiveIncomingFileAtPath:(NSString *)path {
    if (path.length == 0) return;

    NewIssueViewController *composer = gActiveComposer;
    if (composer == nil || composer.navigationController == nil) {
        gPendingIncomingFilePath = [path copy];
        UIAlertView *alert = [[UIAlertView alloc] initWithTitle:GHL(@"Файл получен")
                                                         message:[NSString stringWithFormat:GHL(@"«%@» будет прикреплён, когда вы откроете форму новой задачи."), path.lastPathComponent]
                                                        delegate:nil
                                               cancelButtonTitle:@"OK"
                                               otherButtonTitles:nil];
        [alert show];
        return;
    }

    UINavigationController *navigationController = composer.navigationController;
    if (composer.imagePopover) {
        [composer.imagePopover dismissPopoverAnimated:NO];
        composer.imagePopover = nil;
    }
    if (composer.presentedViewController) [composer dismissViewControllerAnimated:NO completion:nil];
    if (navigationController.tabBarController) navigationController.tabBarController.selectedViewController = navigationController;
    [navigationController popToViewController:composer animated:NO];

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.3 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [composer handleIncomingFileAtPath:path];
    });
}

- (void)handleIncomingFileAtPath:(NSString *)path {
    GHIssueFieldRow *row = self.attachTargetRow;
    if (row.attachButton == nil) {
        row = nil;
        for (GHIssueFieldRow *candidate in self.rows) {
            if (candidate.attachButton) {
                row = candidate;
                break;
            }
        }
    }
    if (row == nil) return;
    if (self.activeUpload) {
        [self showAttachmentError:GHL(@"Дождитесь окончания текущей загрузки и прикрепите файл ещё раз.")];
        return;
    }
    self.attachTargetRow = row;
    [self handlePickedFileAtPath:path forRow:row];
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    gActiveComposer = self;
    if (gPendingIncomingFilePath.length > 0) {
        NSString *path = gPendingIncomingFilePath;
        gPendingIncomingFilePath = nil;
        self.didAutoFocusTitle = YES;
        [self handleIncomingFileAtPath:path];
        return;
    }
    if (self.didAutoFocusTitle) return;
    self.didAutoFocusTitle = YES;
    if (self.titleRow.textField.text.length == 0) [self.titleRow.textField becomeFirstResponder];
}

- (void)dealloc {
    [self.activeUpload cancel];
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

#pragma mark - Building

- (UIView *)makeCard {
    UIView *card = [[UIView alloc] init];
    card.layer.cornerRadius = 8.0;
    card.layer.borderWidth = 1.0;
    card.clipsToBounds = YES;
    [self.scrollView addSubview:card];
    return card;
}

- (GHIssueFieldRow *)buildRowForField:(GHIssueFormField *)field {
    GHIssueFieldRow *row = [[GHIssueFieldRow alloc] init];
    row.field = field;
    row.value = [field initialValue];

    if (field.type == GHIssueFormFieldTypeMarkdown) {
        row.markdownLabel = GHNewIssueMakeLabel([UIFont systemFontOfSize:15]);
        row.markdownLabel.text = GHPlainTextFromMarkdown(field.value);
        [self.scrollView addSubview:row.markdownLabel];
        return row;
    }

    row.captionLabel = GHNewIssueMakeLabel([UIFont boldSystemFontOfSize:15]);
    NSString *caption = GHEmojiForDisplay(field.label);
    BOOL showsRequiredMark = field.required || field.requiredOptionIndexes.count > 0;
    row.captionLabel.text = showsRequiredMark ? [caption stringByAppendingString:@" *"] : caption;
    [self.scrollView addSubview:row.captionLabel];

    if (field.fieldDescription.length > 0) {
        row.descriptionLabel = GHNewIssueMakeLabel([UIFont systemFontOfSize:13]);
        row.descriptionLabel.text = GHPlainTextFromMarkdown(field.fieldDescription);
        [self.scrollView addSubview:row.descriptionLabel];
    }

    row.card = [self makeCard];

    switch (field.type) {
        case GHIssueFormFieldTypeInput: {
            row.textField = [[UITextField alloc] init];
            row.textField.borderStyle = UITextBorderStyleNone;
            row.textField.backgroundColor = [UIColor clearColor];
            row.textField.font = [UIFont systemFontOfSize:16];
            row.textField.contentVerticalAlignment = UIControlContentVerticalAlignmentCenter;
            row.textField.clearButtonMode = UITextFieldViewModeWhileEditing;
            row.textField.placeholder = field.placeholder;
            row.textField.text = row.value;
            row.textField.returnKeyType = UIReturnKeyNext;
            row.textField.delegate = self;
            [row.textField addTarget:self action:@selector(inputChanged:) forControlEvents:UIControlEventEditingChanged];
            [row.card addSubview:row.textField];
            break;
        }
        case GHIssueFormFieldTypeTextarea: {
            row.textView = [[GHPlaceholderTextView alloc] initWithFrame:CGRectZero];
            row.textView.backgroundColor = [UIColor clearColor];
            row.textView.font = field.render.length > 0 ? [UIFont fontWithName:@"Courier" size:14] : [UIFont systemFontOfSize:15];
            row.textView.placeholderLabel.text = GHPlainTextFromMarkdown(field.placeholder);
            row.textView.text = row.value;
            row.textView.delegate = self;
            [row.card addSubview:row.textView];

            if (field.render.length == 0) {
                row.attachButton = [UIButton buttonWithType:UIButtonTypeRoundedRect];
                row.attachButton.titleLabel.font = [UIFont systemFontOfSize:14];
                row.attachButton.contentHorizontalAlignment = UIControlContentHorizontalAlignmentLeft;
                [row.attachButton setTitle:GHL(@"Прикрепить фото или файл…") forState:UIControlStateNormal];
                [row.attachButton addTarget:self action:@selector(attachTapped:) forControlEvents:UIControlEventTouchUpInside];
                [self.scrollView addSubview:row.attachButton];
            }
            break;
        }
        case GHIssueFormFieldTypeDropdown: {
            row.dropdownButton = [UIButton buttonWithType:UIButtonTypeCustom];
            [row.dropdownButton addTarget:self action:@selector(dropdownTapped:) forControlEvents:UIControlEventTouchUpInside];
            [row.card addSubview:row.dropdownButton];

            row.dropdownLabel = GHNewIssueMakeLabel([UIFont systemFontOfSize:16]);
            row.dropdownLabel.numberOfLines = 1;
            row.dropdownLabel.userInteractionEnabled = NO;
            [row.card addSubview:row.dropdownLabel];

            row.dropdownChevron = [[UIImageView alloc] init];
            row.dropdownChevron.userInteractionEnabled = NO;
            [row.card addSubview:row.dropdownChevron];
            break;
        }
        case GHIssueFormFieldTypeCheckboxes: {
            NSMutableArray *labels = [NSMutableArray array];
            NSMutableArray *switches = [NSMutableArray array];
            NSMutableArray *separators = [NSMutableArray array];
            for (NSUInteger i = 0; i < field.options.count; i++) {
                BOOL optionRequired = [field.requiredOptionIndexes containsObject:@(i)];
                UILabel *label = GHNewIssueMakeLabel([UIFont systemFontOfSize:15]);
                NSString *optionText = GHPlainTextFromMarkdown(field.options[i]);
                label.text = optionRequired ? [optionText stringByAppendingString:@" *"] : optionText;
                [row.card addSubview:label];
                [labels addObject:label];

                UISwitch *toggle = [[UISwitch alloc] init];
                [toggle addTarget:self action:@selector(checkboxChanged:) forControlEvents:UIControlEventValueChanged];
                [row.card addSubview:toggle];
                [switches addObject:toggle];

                UIView *separator = [[UIView alloc] init];
                [row.card addSubview:separator];
                [separators addObject:separator];
            }
            row.checkboxLabels = labels;
            row.checkboxSwitches = switches;
            row.checkboxSeparators = separators;
            break;
        }
        default:
            break;
    }

    [self updateDropdownTitleForRow:row];
    return row;
}

- (void)updateDropdownTitleForRow:(GHIssueFieldRow *)row {
    if (row.field.type != GHIssueFormFieldTypeDropdown) return;
    NSMutableArray *selected = [NSMutableArray array];
    [(NSIndexSet *)row.value enumerateIndexesUsingBlock:^(NSUInteger index, BOOL *stop) {
        if (index < row.field.options.count) [selected addObject:row.field.options[index]];
    }];
    row.dropdownLabel.text = selected.count > 0 ? GHEmojiForDisplay([selected componentsJoinedByString:@", "]) : GHL(@"Выберите…");
    row.dropdownLabel.textColor = selected.count > 0 ? GHPrimaryTextColor() : GHSecondaryTextColor();
}

#pragma mark - Theme & layout

- (void)applyTheme {
    BOOL dark = [GHThemeManager sharedManager].darkModeEnabled;
    UIKeyboardAppearance keyboardAppearance = dark ? UIKeyboardAppearanceAlert : UIKeyboardAppearanceDefault;

    self.view.backgroundColor = GHBackgroundColor();
    self.scrollView.backgroundColor = GHBackgroundColor();
    self.repoLabel.textColor = GHSecondaryTextColor();
    self.templateLabel.textColor = GHPrimaryTextColor();
    self.spinner.activityIndicatorViewStyle = GHSpinnerStyle();

    for (GHIssueFieldRow *row in self.rows) {
        row.markdownLabel.textColor = GHPrimaryTextColor();
        row.captionLabel.textColor = GHPrimaryTextColor();
        row.descriptionLabel.textColor = GHSecondaryTextColor();
        row.card.backgroundColor = GHCellBackgroundColor();
        row.card.layer.borderColor = (row.invalid ? GHNewIssueErrorColor() : GHSeparatorColor()).CGColor;

        row.textField.textColor = GHPrimaryTextColor();
        row.textField.keyboardAppearance = keyboardAppearance;
        row.textView.textColor = GHPrimaryTextColor();
        row.textView.keyboardAppearance = keyboardAppearance;
        row.textView.placeholderLabel.textColor = [GHSecondaryTextColor() colorWithAlphaComponent:0.7];
        row.dropdownChevron.image = [GHIconRenderer disclosureChevronWithColor:GHSecondaryTextColor() size:CGSizeMake(12, 20)];
        for (UILabel *label in row.checkboxLabels) label.textColor = GHPrimaryTextColor();
        for (UIView *separator in row.checkboxSeparators) separator.backgroundColor = GHSeparatorColor();
        [self updateDropdownTitleForRow:row];
    }
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    [self layoutContent];
}

- (void)layoutContent {
    CGFloat width = MIN(self.view.bounds.size.width - 24, 640);
    CGFloat left = floor((self.view.bounds.size.width - width) / 2.0);
    CGFloat y = 14;

    CGFloat repoHeight = GHNewIssueLabelHeight(self.repoLabel, width);
    self.repoLabel.frame = CGRectMake(left + 2, y, width - 4, repoHeight);
    y += repoHeight + 2;

    CGFloat templateHeight = GHNewIssueLabelHeight(self.templateLabel, width);
    self.templateLabel.frame = CGRectMake(left + 2, y, width - 4, templateHeight);
    y += templateHeight + 16;

    for (GHIssueFieldRow *row in self.rows) {
        y = [self layoutRow:row atY:y left:left width:width];
    }

    self.submitButton.frame = CGRectMake(left, y + 4, width, 44);
    y += 4 + 44 + 24;

    self.scrollView.contentSize = CGSizeMake(self.view.bounds.size.width, y);
}

- (CGFloat)layoutRow:(GHIssueFieldRow *)row atY:(CGFloat)y left:(CGFloat)left width:(CGFloat)width {
    if (row.field.type == GHIssueFormFieldTypeMarkdown) {
        CGFloat height = GHNewIssueLabelHeight(row.markdownLabel, width - 4);
        row.markdownLabel.frame = CGRectMake(left + 2, y, width - 4, height);
        return y + height + 18;
    }

    CGFloat captionHeight = GHNewIssueLabelHeight(row.captionLabel, width - 4);
    row.captionLabel.frame = CGRectMake(left + 2, y, width - 4, captionHeight);
    y += captionHeight + 4;

    if (row.descriptionLabel) {
        CGFloat descriptionHeight = GHNewIssueLabelHeight(row.descriptionLabel, width - 4);
        row.descriptionLabel.frame = CGRectMake(left + 2, y, width - 4, descriptionHeight);
        y += descriptionHeight + 6;
    }

    CGFloat cardHeight = kInputHeight;
    switch (row.field.type) {
        case GHIssueFormFieldTypeInput:
            row.textField.frame = CGRectMake(10, 0, width - 20, kInputHeight);
            break;
        case GHIssueFormFieldTypeTextarea:
            cardHeight = row.isBody ? kBodyTextareaHeight : kTextareaHeight;
            row.textView.frame = CGRectMake(2, 2, width - 4, cardHeight - 4);
            break;
        case GHIssueFormFieldTypeDropdown:
            row.dropdownButton.frame = CGRectMake(0, 0, width, kInputHeight);
            row.dropdownLabel.frame = CGRectMake(12, 0, width - 12 - 34, kInputHeight);
            row.dropdownChevron.frame = CGRectMake(width - 26, floor((kInputHeight - 20) / 2.0), 12, 20);
            break;
        case GHIssueFormFieldTypeCheckboxes: {
            CGFloat innerY = 0;
            CGFloat separatorHeight = 1.0 / [UIScreen mainScreen].scale;
            for (NSUInteger i = 0; i < row.checkboxSwitches.count; i++) {
                UISwitch *toggle = row.checkboxSwitches[i];
                UILabel *label = row.checkboxLabels[i];
                UIView *separator = row.checkboxSeparators[i];
                CGSize switchSize = toggle.bounds.size;
                CGFloat labelWidth = width - 24 - switchSize.width - 10;
                CGFloat labelHeight = GHNewIssueLabelHeight(label, labelWidth);
                CGFloat rowHeight = MAX(labelHeight + 22, switchSize.height + 16);
                label.frame = CGRectMake(12, innerY + floor((rowHeight - labelHeight) / 2.0), labelWidth, labelHeight);
                toggle.frame = CGRectMake(width - 12 - switchSize.width, innerY + floor((rowHeight - switchSize.height) / 2.0),
                                          switchSize.width, switchSize.height);
                separator.frame = CGRectMake(12, innerY + rowHeight - separatorHeight, width - 12, separatorHeight);
                separator.hidden = (i + 1 == row.checkboxSwitches.count);
                innerY += rowHeight;
            }
            cardHeight = innerY;
            break;
        }
        default:
            break;
    }
    row.card.frame = CGRectMake(left, y, width, cardHeight);
    y += cardHeight;

    if (row.attachButton) {
        row.attachButton.frame = CGRectMake(left + 2, y + 4, width - 4, 30);
        y += 4 + 30;
    }
    return y + 20;
}

#pragma mark - Editing

- (GHIssueFieldRow *)rowContainingView:(UIView *)view {
    for (GHIssueFieldRow *row in self.rows) {
        if ([view isDescendantOfView:row.card] || (row.attachButton && view == row.attachButton)) return row;
    }
    return nil;
}

- (void)clearInvalidStateForRow:(GHIssueFieldRow *)row {
    if (!row.invalid) return;
    row.invalid = NO;
    row.card.layer.borderColor = GHSeparatorColor().CGColor;
}

- (void)inputChanged:(UITextField *)textField {
    [self clearInvalidStateForRow:[self rowContainingView:textField]];
}

- (void)checkboxChanged:(UISwitch *)toggle {
    GHIssueFieldRow *row = [self rowContainingView:toggle];
    if ([row.field isSatisfiedByValue:[row currentValue]]) [self clearInvalidStateForRow:row];
}

- (void)dropdownTapped:(UIButton *)button {
    [self dismissKeyboard];
    GHIssueFieldRow *row = [self rowContainingView:button];
    if (row == nil) return;

    GHIssueOptionsViewController *optionsVC = [[GHIssueOptionsViewController alloc] initWithStyle:UITableViewStylePlain];
    optionsVC.title = GHEmojiForDisplay(row.field.label);
    optionsVC.options = row.field.options;
    optionsVC.multiple = row.field.multiple;
    optionsVC.allowsNone = !row.field.required;
    optionsVC.selection = row.value;
    __weak typeof(self) weakSelf = self;
    __weak GHIssueFieldRow *weakRow = row;
    optionsVC.onChange = ^{
        GHIssueFieldRow *strongRow = weakRow;
        if (strongRow == nil) return;
        [weakSelf updateDropdownTitleForRow:strongRow];
        if ([strongRow.field isSatisfiedByValue:strongRow.value]) [weakSelf clearInvalidStateForRow:strongRow];
    };
    [self.navigationController pushViewController:optionsVC animated:YES];
}

#pragma mark - Attachments

- (void)attachTapped:(UIButton *)button {
    [self dismissKeyboard];
    GHIssueFieldRow *row = [self rowContainingView:button];
    if (row == nil || self.activeUpload != nil) return;
    self.attachTargetRow = row;

    UIActionSheet *sheet = [[UIActionSheet alloc] initWithTitle:nil
                                                       delegate:self
                                              cancelButtonTitle:nil
                                         destructiveButtonTitle:nil
                                              otherButtonTitles:nil];
    NSMutableArray *actions = [NSMutableArray array];
    [sheet addButtonWithTitle:GHL(@"Фото из медиатеки")];
    [actions addObject:@"library"];
    if ([UIImagePickerController isSourceTypeAvailable:UIImagePickerControllerSourceTypeCamera]) {
        [sheet addButtonWithTitle:GHL(@"Снять фото")];
        [actions addObject:@"camera"];
    }
    [sheet addButtonWithTitle:GHL(@"Файл…")];
    [actions addObject:@"file"];
    sheet.cancelButtonIndex = [sheet addButtonWithTitle:GHL(@"Отмена")];
    self.attachActions = actions;

    if (UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPad) {
        [sheet showFromRect:button.frame inView:self.scrollView animated:YES];
    } else {
        [sheet showInView:self.view];
    }
}

- (void)actionSheet:(UIActionSheet *)actionSheet clickedButtonAtIndex:(NSInteger)buttonIndex {
    if (buttonIndex == actionSheet.cancelButtonIndex || buttonIndex < 0 || buttonIndex >= (NSInteger)self.attachActions.count) return;
    NSString *action = self.attachActions[buttonIndex];

    if ([action isEqualToString:@"file"]) {
        [self presentFileBrowser];
        return;
    }

    UIImagePickerControllerSourceType sourceType = [action isEqualToString:@"camera"]
        ? UIImagePickerControllerSourceTypeCamera
        : UIImagePickerControllerSourceTypePhotoLibrary;
    __weak typeof(self) weakSelf = self;
    [self ensureUploadAccess:^{
        [weakSelf presentImagePickerWithSourceType:sourceType];
    }];
}

- (void)presentFileBrowser {
    GHFileBrowserViewController *browserVC = [[GHFileBrowserViewController alloc] init];
    __weak typeof(self) weakSelf = self;
    __weak GHIssueFieldRow *weakRow = self.attachTargetRow;
    browserVC.onFilePicked = ^(NSString *path) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        GHIssueFieldRow *strongRow = weakRow;
        if (!strongSelf || !strongRow) return;
        [strongSelf.navigationController popToViewController:strongSelf animated:YES];
        [strongSelf handlePickedFileAtPath:path forRow:strongRow];
    };
    [self.navigationController pushViewController:browserVC animated:YES];
}

- (void)handlePickedFileAtPath:(NSString *)path forRow:(GHIssueFieldRow *)row {
    if (![[NSFileManager defaultManager] isReadableFileAtPath:path]) {
        [self showUnreadableFileAlertForPath:path];
        return;
    }
    NSString *contentType = [GHAttachmentUploader contentTypeForFileName:path];
    if (contentType == nil) {
        [self insertTextFileAtPath:path intoRow:row];
        return;
    }

    unsigned long long size = [[[NSFileManager defaultManager] attributesOfItemAtPath:path error:nil] fileSize];
    unsigned long long maximum = [GHAttachmentUploader maximumSizeForContentType:contentType];
    if (size == 0 || size > maximum) {
        [self showAttachmentError:[NSString stringWithFormat:GHL(@"Файл пустой или слишком большой: можно не больше %llu МБ."),
                                   maximum / (1024 * 1024)]];
        return;
    }

    __weak typeof(self) weakSelf = self;
    __weak GHIssueFieldRow *weakRow = row;
    [self ensureUploadAccess:^{
        NSData *data = [NSData dataWithContentsOfFile:path options:NSDataReadingMappedIfSafe error:nil];
        if (data.length == 0) {
            [weakSelf showAttachmentError:GHL(@"Не удалось прочитать файл.")];
            return;
        }
        GHIssueFieldRow *strongRow = weakRow;
        if (strongRow) [weakSelf uploadData:data fileName:path.lastPathComponent contentType:contentType intoRow:strongRow];
    }];
}

- (void)ensureUploadAccess:(void (^)(void))then {
    if (self.uploadRepositoryID > 0) {
        then();
        return;
    }

    [self setAttachButtonsTitle:GHL(@"Проверка доступа…") enabled:NO];
    __weak typeof(self) weakSelf = self;
    [[GHAPIClient sharedClient] repoDetailForOwner:self.ownerLogin repo:self.repoName completion:^(id jsonObject, NSError *error) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;
        [strongSelf setAttachButtonsTitle:nil enabled:YES];

        NSDictionary *repo = [jsonObject isKindOfClass:[NSDictionary class]] ? jsonObject : nil;
        if (repo == nil) {
            [strongSelf showAttachmentError:error.localizedDescription ?: GHL(@"неизвестная ошибка")];
            return;
        }
        if ([strongSelf adoptUploadRepository:repo requirePublic:NO]) {
            then();
            return;
        }
        [strongSelf findPublicUploadRepositoryThen:then];
    }];
}

- (BOOL)adoptUploadRepository:(NSDictionary *)repo requirePublic:(BOOL)requirePublic {
    if (![repo isKindOfClass:[NSDictionary class]]) return NO;
    NSDictionary *permissions = [repo[@"permissions"] isKindOfClass:[NSDictionary class]] ? repo[@"permissions"] : nil;
    id repositoryID = repo[@"id"];
    if (![permissions[@"push"] boolValue] || ![repositoryID respondsToSelector:@selector(longLongValue)]) return NO;
    if ([repo[@"archived"] boolValue] || [repo[@"disabled"] boolValue]) return NO;
    if (requirePublic && [repo[@"private"] boolValue]) return NO;

    self.uploadRepositoryID = [repositoryID longLongValue];
    id fullName = repo[@"full_name"];
    self.uploadRepositoryFullName = [fullName isKindOfClass:[NSString class]] ? fullName : nil;
    return YES;
}

- (void)findPublicUploadRepositoryThen:(void (^)(void))then {
    [self setAttachButtonsTitle:GHL(@"Проверка доступа…") enabled:NO];
    __weak typeof(self) weakSelf = self;
    [[GHAPIClient sharedClient] publicRepositoriesForCurrentUserWithCompletion:^(id jsonObject, NSError *error) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;
        [strongSelf setAttachButtonsTitle:nil enabled:YES];

        if (![jsonObject isKindOfClass:[NSArray class]]) {
            [strongSelf showAttachmentError:error.localizedDescription ?: GHL(@"неизвестная ошибка")];
            return;
        }
        for (id repo in jsonObject) {
            if ([strongSelf adoptUploadRepository:repo requirePublic:YES]) {
                then();
                return;
            }
        }

        UIAlertView *alert = [[UIAlertView alloc] initWithTitle:GHL(@"Фото и видео недоступны")
                                                         message:[NSString stringWithFormat:GHL(@"В %@/%@ у вас нет права записи, а GitHub загружает фото и видео только с привязкой к репозиторию, где такое право есть. Обычно для этого используется ваш собственный публичный репозиторий (в него ничего не добавляется), но у вас его нет.\n\nЛоги и текстовые файлы можно вставить в задачу текстом через «Файл…»."),
                                                                  strongSelf.ownerLogin, strongSelf.repoName]
                                                        delegate:nil
                                               cancelButtonTitle:@"OK"
                                               otherButtonTitles:nil];
        [alert show];
    }];
}

- (void)setAttachButtonsTitle:(NSString *)title enabled:(BOOL)enabled {
    for (GHIssueFieldRow *row in self.rows) {
        if (row.attachButton == nil) continue;
        [row.attachButton setTitle:title ?: GHL(@"Прикрепить фото или файл…") forState:UIControlStateNormal];
        row.attachButton.enabled = enabled;
    }
}

- (void)presentImagePickerWithSourceType:(UIImagePickerControllerSourceType)sourceType {
    if (![UIImagePickerController isSourceTypeAvailable:sourceType]) return;

    UIImagePickerController *picker = [[UIImagePickerController alloc] init];
    picker.sourceType = sourceType;
    picker.delegate = self;

    if (UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPad && sourceType != UIImagePickerControllerSourceTypeCamera) {
        self.imagePopover = [[UIPopoverController alloc] initWithContentViewController:picker];
        [self.imagePopover presentPopoverFromRect:self.attachTargetRow.attachButton.frame
                                           inView:self.scrollView
                         permittedArrowDirections:UIPopoverArrowDirectionAny
                                         animated:YES];
        return;
    }
    [self presentViewController:picker animated:YES completion:nil];
}

- (void)dismissImagePicker:(UIImagePickerController *)picker {
    if (self.imagePopover) {
        [self.imagePopover dismissPopoverAnimated:YES];
        self.imagePopover = nil;
    } else {
        [picker dismissViewControllerAnimated:YES completion:nil];
    }
}

- (void)imagePickerControllerDidCancel:(UIImagePickerController *)picker {
    [self dismissImagePicker:picker];
}

- (void)imagePickerController:(UIImagePickerController *)picker didFinishPickingMediaWithInfo:(NSDictionary *)info {
    UIImage *image = info[UIImagePickerControllerOriginalImage];
    [self dismissImagePicker:picker];
    GHIssueFieldRow *row = self.attachTargetRow;
    if (![image isKindOfClass:[UIImage class]] || row == nil) return;

    NSData *data = [self jpegDataForImage:image];
    if (data.length == 0) {
        [self showAttachmentError:GHL(@"Не удалось подготовить фото.")];
        return;
    }

    NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
    formatter.locale = [[NSLocale alloc] initWithLocaleIdentifier:@"en_US_POSIX"];
    formatter.dateFormat = @"yyyyMMdd_HHmmss";
    NSString *fileName = [NSString stringWithFormat:@"IMG_%@.jpg", [formatter stringFromDate:[NSDate date]]];
    [self uploadData:data fileName:fileName contentType:@"image/jpeg" intoRow:row];
}

- (NSData *)jpegDataForImage:(UIImage *)image {
    CGSize size = image.size;
    CGFloat longest = MAX(size.width, size.height);
    CGFloat scale = longest > kMaxPhotoDimension ? kMaxPhotoDimension / longest : 1.0;
    CGSize target = CGSizeMake(floor(size.width * scale), floor(size.height * scale));
    if (target.width < 1 || target.height < 1) return nil;

    UIGraphicsBeginImageContextWithOptions(target, YES, 1.0);
    [image drawInRect:CGRectMake(0, 0, target.width, target.height)];
    UIImage *normalized = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();

    CGFloat quality = 0.85;
    NSData *data = UIImageJPEGRepresentation(normalized, quality);
    while (data.length > [GHAttachmentUploader maximumSizeForContentType:@"image/jpeg"] && quality > 0.3) {
        quality -= 0.15;
        data = UIImageJPEGRepresentation(normalized, quality);
    }
    return data;
}

- (void)uploadData:(NSData *)data fileName:(NSString *)fileName contentType:(NSString *)contentType intoRow:(GHIssueFieldRow *)row {
    NSString *placeholder = [NSString stringWithFormat:@"![%@ %@…]()", GHL(@"Загрузка"), fileName];
    [self insertBlock:placeholder intoRow:row];
    [self setAttachButtonsTitle:[self uploadProgressTitle:0] enabled:NO];

    __weak typeof(self) weakSelf = self;
    __weak GHIssueFieldRow *weakRow = row;
    self.activeUpload = [GHAttachmentUploader uploadData:data
                                                fileName:fileName
                                             contentType:contentType
                                            repositoryID:self.uploadRepositoryID
                                                progress:^(float progress) {
        [weakSelf setAttachButtonsTitle:[weakSelf uploadProgressTitle:(int)(progress * 100)] enabled:NO];
    } completion:^(NSString *url, NSError *error) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;
        strongSelf.activeUpload = nil;
        [strongSelf setAttachButtonsTitle:nil enabled:YES];

        GHIssueFieldRow *strongRow = weakRow;
        NSString *replacement = url ? [GHAttachmentUploader markdownForFileName:fileName url:url contentType:contentType] : @"";
        if (strongRow) [strongSelf replacePlaceholder:placeholder withText:replacement inRow:strongRow];
        if (url == nil) [strongSelf showAttachmentError:error.localizedDescription ?: GHL(@"неизвестная ошибка")];
    }];
}

- (NSString *)uploadProgressTitle:(int)percent {
    NSString *target = [NSString stringWithFormat:@"%@/%@", self.ownerLogin, self.repoName];
    if (self.uploadRepositoryFullName.length > 0 && [self.uploadRepositoryFullName caseInsensitiveCompare:target] != NSOrderedSame) {
        return [NSString stringWithFormat:GHL(@"Загрузка через %@… %d%%"), self.uploadRepositoryFullName, percent];
    }
    return [NSString stringWithFormat:GHL(@"Загрузка… %d%%"), percent];
}

- (void)replacePlaceholder:(NSString *)placeholder withText:(NSString *)replacement inRow:(GHIssueFieldRow *)row {
    NSString *current = row.textView.text ?: @"";
    NSRange range = [current rangeOfString:placeholder];
    if (range.location == NSNotFound) {
        if (replacement.length > 0) [self insertBlock:replacement intoRow:row];
        return;
    }
    if (replacement.length == 0 && NSMaxRange(range) < current.length && [current characterAtIndex:NSMaxRange(range)] == '\n') {
        range.length += 1;
    }
    row.textView.text = [current stringByReplacingCharactersInRange:range withString:replacement];
}

- (void)insertBlock:(NSString *)block intoRow:(GHIssueFieldRow *)row {
    UITextView *textView = row.textView;
    NSString *current = textView.text ?: @"";
    NSRange selection = textView.selectedRange;
    if (selection.location == NSNotFound || NSMaxRange(selection) > current.length) {
        selection = NSMakeRange(current.length, 0);
    }
    NSString *before = [current substringToIndex:selection.location];
    NSString *prefix = (before.length == 0 || [before hasSuffix:@"\n\n"]) ? @"" : ([before hasSuffix:@"\n"] ? @"\n" : @"\n\n");
    NSString *insertion = [NSString stringWithFormat:@"%@%@\n", prefix, block];

    textView.text = [current stringByReplacingCharactersInRange:selection withString:insertion];
    textView.selectedRange = NSMakeRange(selection.location + insertion.length, 0);
    [self clearInvalidStateForRow:row];
}

- (NSString *)unreadableFileMessageForPath:(NSString *)path {
    NSDictionary *attributes = [[NSFileManager defaultManager] attributesOfItemAtPath:path error:nil];
    NSString *owner = attributes[NSFileOwnerAccountName] ?: @"?";
    unsigned long permissions = [attributes[NSFilePosixPermissions] unsignedLongValue];
    return [NSString stringWithFormat:GHL(@"Нет доступа на чтение: файл принадлежит %@ (права %lo), а приложение работает от пользователя mobile.\n\nОткройте папку с файлом в файловом менеджере, выберите файл и нажмите «Открыть в…» → GitHub — он сразу прикрепится к задаче."),
            owner, permissions];
}

- (void)showUnreadableFileAlertForPath:(NSString *)path {
    NSString *encodedFolder = [[path stringByDeletingLastPathComponent] stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding];
    NSArray *candidates = @[@[GHL(@"Открыть в Filza"), [NSString stringWithFormat:@"filza://view%@", encodedFolder]],
                            @[GHL(@"Открыть в iFile"), [NSString stringWithFormat:@"ifile://%@", encodedFolder]]];

    UIAlertView *alert = [[UIAlertView alloc] initWithTitle:GHL(@"Не удалось прикрепить файл")
                                                     message:[self unreadableFileMessageForPath:path]
                                                    delegate:self
                                           cancelButtonTitle:nil
                                           otherButtonTitles:nil];
    NSMutableArray *urls = [NSMutableArray array];
    for (NSArray *candidate in candidates) {
        NSURL *url = [NSURL URLWithString:candidate[1]];
        if (url == nil || ![[UIApplication sharedApplication] canOpenURL:url]) continue;
        [alert addButtonWithTitle:candidate[0]];
        [urls addObject:url];
    }
    alert.cancelButtonIndex = [alert addButtonWithTitle:urls.count > 0 ? GHL(@"Отмена") : @"OK"];
    alert.tag = kUnreadableFileAlertTag;
    self.fileManagerURLs = urls;
    [alert show];
}

- (void)alertView:(UIAlertView *)alertView clickedButtonAtIndex:(NSInteger)buttonIndex {
    if (alertView.tag != kUnreadableFileAlertTag || buttonIndex == alertView.cancelButtonIndex) return;
    if (buttonIndex < 0 || buttonIndex >= (NSInteger)self.fileManagerURLs.count) return;
    [[UIApplication sharedApplication] openURL:self.fileManagerURLs[buttonIndex]];
}

- (void)showAttachmentError:(NSString *)message {
    UIAlertView *alert = [[UIAlertView alloc] initWithTitle:GHL(@"Не удалось прикрепить файл")
                                                     message:message
                                                    delegate:nil
                                           cancelButtonTitle:@"OK"
                                           otherButtonTitles:nil];
    [alert show];
}

- (NSString *)textContentsOfFileAtPath:(NSString *)path
                           totalLength:(unsigned long long *)totalLength
                          errorMessage:(NSString **)errorMessage {
    NSFileHandle *handle = [NSFileHandle fileHandleForReadingAtPath:path];
    if (handle == nil) {
        *errorMessage = [self unreadableFileMessageForPath:path];
        return nil;
    }

    unsigned long long length = [handle seekToEndOfFile];
    if (totalLength != NULL) *totalLength = length;
    unsigned long long readLength = MIN(length, (unsigned long long)kMaxFileReadBytes);
    [handle seekToFileOffset:length - readLength];
    NSData *raw = [handle readDataOfLength:(NSUInteger)readLength];
    [handle closeFile];

    NSMutableData *data = [NSMutableData dataWithCapacity:raw.length];
    const unsigned char *bytes = raw.bytes;
    NSUInteger controlBytes = 0;
    NSUInteger start = 0;
    for (NSUInteger i = 0; i <= raw.length; i++) {
        if (i < raw.length && bytes[i] != 0) {
            unsigned char c = bytes[i];
            if ((c < 0x20 && c != '\t' && c != '\n' && c != '\r' && c != 0x1B) || c == 0x7F) controlBytes++;
            continue;
        }
        if (i > start) [data appendBytes:bytes + start length:i - start];
        start = i + 1;
    }

    if (data.length == 0) {
        *errorMessage = GHL(@"Файл пустой.");
        return nil;
    }
    if (controlBytes * 20 > data.length) {
        *errorMessage = [NSString stringWithFormat:GHL(@"Этот файл нельзя прикрепить. GitHub принимает фото и видео (%@), а текстовые файлы — логи, конфиги — вставляются в задачу текстом."),
                         [GHAttachmentUploader supportedExtensionsDescription]];
        return nil;
    }

    NSString *text = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    if (text == nil && readLength < length) {
        for (NSUInteger skip = 1; skip < 4 && skip < data.length && text == nil; skip++) {
            NSData *trimmed = [data subdataWithRange:NSMakeRange(skip, data.length - skip)];
            text = [[NSString alloc] initWithData:trimmed encoding:NSUTF8StringEncoding];
        }
    }
    if (text == nil) text = [[NSString alloc] initWithData:data encoding:NSISOLatin1StringEncoding];

    static NSRegularExpression *ansiRegex = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        ansiRegex = [NSRegularExpression regularExpressionWithPattern:@"\\x1B\\[[0-9;?]*[A-Za-z]" options:0 error:nil];
    });
    text = [ansiRegex stringByReplacingMatchesInString:text options:0 range:NSMakeRange(0, text.length) withTemplate:@""];
    return [text stringByReplacingOccurrencesOfString:@"\r\n" withString:@"\n"];
}

- (NSUInteger)longestBacktickRunInString:(NSString *)text {
    NSUInteger longest = 0;
    NSUInteger current = 0;
    for (NSUInteger i = 0; i < text.length; i++) {
        current = [text characterAtIndex:i] == '`' ? current + 1 : 0;
        longest = MAX(longest, current);
    }
    return longest;
}

- (void)insertTextFileAtPath:(NSString *)path intoRow:(GHIssueFieldRow *)row {
    unsigned long long fileLength = 0;
    NSString *errorMessage = nil;
    NSString *contents = [self textContentsOfFileAtPath:path totalLength:&fileLength errorMessage:&errorMessage];
    if (contents == nil) {
        [self showAttachmentError:errorMessage ?: GHL(@"Не удалось прочитать файл.")];
        return;
    }

    NSString *fileName = path.lastPathComponent;
    NSString *bodySoFar = [self composedBody];
    NSInteger budget = (NSInteger)kMaxIssueBodyLength - (NSInteger)bodySoFar.length - 200 - (NSInteger)fileName.length;
    if (budget < 500) {
        [self showAttachmentError:GHL(@"В тексте задачи не осталось места: GitHub ограничивает его 65 536 символами.")];
        return;
    }

    NSUInteger limit = MIN((NSUInteger)budget, kMaxInlineFileCharacters);
    BOOL truncated = fileLength > kMaxFileReadBytes;
    if (contents.length > limit) {
        NSRange cut = [contents rangeOfString:@"\n" options:0 range:NSMakeRange(contents.length - limit, limit)];
        NSUInteger start = cut.location != NSNotFound ? cut.location + 1 : contents.length - limit;
        contents = [contents substringFromIndex:start];
        truncated = YES;
    }
    contents = [contents stringByTrimmingCharactersInSet:[NSCharacterSet newlineCharacterSet]];

    NSString *fence = [@"" stringByPaddingToLength:MAX((NSUInteger)3, [self longestBacktickRunInString:contents] + 1)
                                         withString:@"`"
                                    startingAtIndex:0];
    NSMutableString *snippet = [NSMutableString stringWithFormat:@"<details><summary>%@</summary>\n\n", fileName];
    if (truncated) {
        [snippet appendFormat:GHL(@"_Показан конец файла: последние %lu строк._\n\n"),
                              (unsigned long)[[contents componentsSeparatedByString:@"\n"] count]];
    }
    [snippet appendFormat:@"%@\n%@\n%@\n\n</details>", fence, contents, fence];
    [self insertBlock:snippet intoRow:row];
}

- (void)textFieldDidBeginEditing:(UITextField *)textField {
    self.activeInputView = textField;
    [self scrollActiveInputIntoView];
}

- (BOOL)textFieldShouldReturn:(UITextField *)textField {
    NSUInteger index = [self.rows indexOfObject:[self rowContainingView:textField]];
    for (NSUInteger i = index + 1; index != NSNotFound && i < self.rows.count; i++) {
        GHIssueFieldRow *next = self.rows[i];
        UIView *input = next.textField ?: next.textView;
        if (input) {
            [input becomeFirstResponder];
            return NO;
        }
    }
    [textField resignFirstResponder];
    return NO;
}

- (void)textViewDidBeginEditing:(UITextView *)textView {
    self.activeInputView = textView;
    [self scrollActiveInputIntoView];
}

- (void)textViewDidChange:(UITextView *)textView {
    [self clearInvalidStateForRow:[self rowContainingView:textView]];
}

- (void)dismissKeyboard {
    [self.view endEditing:YES];
}

- (void)scrollActiveInputIntoView {
    UIView *input = self.activeInputView;
    if (input == nil || input.superview == nil) return;
    CGRect rect = [input.superview convertRect:input.frame toView:self.scrollView];
    [self.scrollView scrollRectToVisible:CGRectInset(rect, 0, -12) animated:YES];
}

- (void)keyboardWillShow:(NSNotification *)notification {
    CGRect keyboardFrame = [[notification.userInfo objectForKey:UIKeyboardFrameEndUserInfoKey] CGRectValue];
    CGRect converted = [self.view convertRect:keyboardFrame fromView:nil];
    CGFloat overlap = MAX(0, CGRectGetMaxY(self.view.bounds) - CGRectGetMinY(converted));
    UIEdgeInsets insets = self.scrollView.contentInset;
    insets.bottom = overlap;
    self.scrollView.contentInset = insets;
    self.scrollView.scrollIndicatorInsets = insets;
    [self scrollActiveInputIntoView];
}

- (void)keyboardWillHide:(NSNotification *)notification {
    UIEdgeInsets insets = self.scrollView.contentInset;
    insets.bottom = 0;
    self.scrollView.contentInset = insets;
    self.scrollView.scrollIndicatorInsets = insets;
}

#pragma mark - Submitting

- (void)setSubmitting:(BOOL)submitting {
    _submitting = submitting;
    self.submitButton.enabled = !submitting;
    self.scrollView.userInteractionEnabled = !submitting;
    self.navigationItem.hidesBackButton = submitting;
    if (submitting) {
        [self.spinner startAnimating];
        self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithCustomView:self.spinner];
    } else {
        [self.spinner stopAnimating];
        self.navigationItem.rightBarButtonItem = self.submitItem;
    }
}

- (NSString *)composedBody {
    if (!self.issueTemplate.isForm) {
        for (GHIssueFieldRow *row in self.rows) {
            if (row.isBody) return [row currentValue];
        }
        return @"";
    }

    NSMutableArray *sections = [NSMutableArray array];
    for (GHIssueFieldRow *row in self.rows) {
        if (row == self.titleRow) continue;
        NSString *section = [row.field bodySectionWithValue:[row currentValue]];
        if (section.length > 0) [sections addObject:section];
    }
    return [sections componentsJoinedByString:@"\n\n"];
}

- (void)submitTapped {
    if (self.submitting) return;
    if (self.activeUpload) {
        UIAlertView *alert = [[UIAlertView alloc] initWithTitle:GHL(@"Файл ещё загружается")
                                                         message:GHL(@"Дождитесь окончания загрузки и отправьте задачу ещё раз.")
                                                        delegate:nil
                                               cancelButtonTitle:@"OK"
                                               otherButtonTitles:nil];
        [alert show];
        return;
    }
    [self dismissKeyboard];

    NSMutableArray *missing = [NSMutableArray array];
    GHIssueFieldRow *firstInvalid = nil;
    for (GHIssueFieldRow *row in self.rows) {
        BOOL valid = [row.field isSatisfiedByValue:[row currentValue]];
        row.invalid = !valid;
        row.card.layer.borderColor = (valid ? GHSeparatorColor() : GHNewIssueErrorColor()).CGColor;
        if (valid) continue;
        if (firstInvalid == nil) firstInvalid = row;
        [missing addObject:[NSString stringWithFormat:@"• %@", GHEmojiForDisplay(row.field.label)]];
    }

    if (firstInvalid) {
        CGRect target = CGRectUnion(firstInvalid.captionLabel.frame, firstInvalid.card.frame);
        [self.scrollView scrollRectToVisible:CGRectInset(target, 0, -12) animated:YES];
        UIAlertView *alert = [[UIAlertView alloc] initWithTitle:GHL(@"Заполните обязательные поля")
                                                         message:[missing componentsJoinedByString:@"\n"]
                                                        delegate:nil
                                               cancelButtonTitle:@"OK"
                                               otherButtonTitles:nil];
        [alert show];
        return;
    }

    NSString *title = [[self.titleRow currentValue] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    NSMutableDictionary *parameters = [NSMutableDictionary dictionaryWithObject:title forKey:@"title"];
    NSString *body = [self composedBody];
    if (body.length > kMaxIssueBodyLength) {
        UIAlertView *alert = [[UIAlertView alloc] initWithTitle:GHL(@"Слишком длинный текст")
                                                         message:[NSString stringWithFormat:GHL(@"GitHub принимает не больше %lu символов, а в задаче %lu. Сократите текст или вложенные файлы."),
                                                                  (unsigned long)kMaxIssueBodyLength, (unsigned long)body.length]
                                                        delegate:nil
                                               cancelButtonTitle:@"OK"
                                               otherButtonTitles:nil];
        [alert show];
        return;
    }
    if (body.length > 0) parameters[@"body"] = body;
    if (self.issueTemplate.labels.count > 0) parameters[@"labels"] = self.issueTemplate.labels;
    if (self.issueTemplate.assignees.count > 0) parameters[@"assignees"] = self.issueTemplate.assignees;

    self.submitting = YES;
    [self sendIssueWithParameters:parameters allowRetry:YES];
}

- (void)sendIssueWithParameters:(NSDictionary *)parameters allowRetry:(BOOL)allowRetry {
    __weak typeof(self) weakSelf = self;
    [[GHAPIClient sharedClient] createIssueForOwner:self.ownerLogin
                                                repo:self.repoName
                                          parameters:parameters
                                          completion:^(id jsonObject, NSError *error) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;

        BOOL hasMetadata = parameters[@"labels"] != nil || parameters[@"assignees"] != nil;
        if (error && allowRetry && hasMetadata && error.code == 422) {
            NSMutableDictionary *plain = [parameters mutableCopy];
            [plain removeObjectForKey:@"labels"];
            [plain removeObjectForKey:@"assignees"];
            [strongSelf sendIssueWithParameters:plain allowRetry:NO];
            return;
        }

        strongSelf.submitting = NO;
        if (error || ![jsonObject isKindOfClass:[NSDictionary class]]) {
            NSString *message = error.localizedDescription ?: GHL(@"неизвестная ошибка");
            if (error.code == 403 || error.code == 404) {
                message = [NSString stringWithFormat:@"%@\n\n%@", message,
                           GHL(@"Возможно, у вашего токена нет прав на создание задач. Для classic-токена нужен scope «public_repo» (или «repo» для приватных репозиториев), для fine-grained — разрешение «Issues: Read and write».")];
            }
            UIAlertView *alert = [[UIAlertView alloc] initWithTitle:GHL(@"Не удалось создать задачу")
                                                             message:message
                                                            delegate:nil
                                                   cancelButtonTitle:@"OK"
                                                   otherButtonTitles:nil];
            [alert show];
            return;
        }

        if (strongSelf.onIssueCreated) {
            strongSelf.onIssueCreated(jsonObject);
            return;
        }
        IssueDetailViewController *detailVC = [[IssueDetailViewController alloc] init];
        detailVC.issue = jsonObject;
        detailVC.ownerLogin = strongSelf.ownerLogin;
        detailVC.repoName = strongSelf.repoName;
        [strongSelf.navigationController pushViewController:detailVC animated:YES];
    }];
}

@end
