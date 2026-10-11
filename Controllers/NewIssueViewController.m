#import "NewIssueViewController.h"
#import <QuartzCore/QuartzCore.h>
#import "IssueDetailViewController.h"
#import "GHIssueTemplate.h"
#import "GHAPIClient.h"
#import "GHThemeManager.h"
#import "GHLocalization.h"
#import "GHIconRenderer.h"
#import "GHCompat.h"

static const CGFloat kInputHeight = 44;
static const CGFloat kTextareaHeight = 140;
static const CGFloat kBodyTextareaHeight = 260;

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

@interface NewIssueViewController () <UITextFieldDelegate, UITextViewDelegate>
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

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    if (self.didAutoFocusTitle) return;
    self.didAutoFocusTitle = YES;
    if (self.titleRow.textField.text.length == 0) [self.titleRow.textField becomeFirstResponder];
}

- (void)dealloc {
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
    return y + cardHeight + 20;
}

#pragma mark - Editing

- (GHIssueFieldRow *)rowContainingView:(UIView *)view {
    for (GHIssueFieldRow *row in self.rows) {
        if ([view isDescendantOfView:row.card]) return row;
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
