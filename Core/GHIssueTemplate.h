#import <Foundation/Foundation.h>

typedef NS_ENUM(NSInteger, GHIssueFormFieldType) {
    GHIssueFormFieldTypeMarkdown,
    GHIssueFormFieldTypeInput,
    GHIssueFormFieldTypeTextarea,
    GHIssueFormFieldTypeDropdown,
    GHIssueFormFieldTypeCheckboxes
};

@interface GHIssueFormField : NSObject

@property (nonatomic, assign) GHIssueFormFieldType type;
@property (nonatomic, copy) NSString *label;
@property (nonatomic, copy) NSString *fieldDescription;
@property (nonatomic, copy) NSString *placeholder;
@property (nonatomic, copy) NSString *value;
@property (nonatomic, copy) NSString *render;
@property (nonatomic, copy) NSArray *options;
@property (nonatomic, copy) NSArray *requiredOptionIndexes;
@property (nonatomic, assign) BOOL multiple;
@property (nonatomic, assign) NSInteger defaultIndex;
@property (nonatomic, assign) BOOL required;

+ (instancetype)fieldWithDictionary:(NSDictionary *)dictionary;

- (id)initialValue;
- (BOOL)isSatisfiedByValue:(id)value;
- (NSString *)bodySectionWithValue:(id)value;

@end

@interface GHIssueTemplate : NSObject

@property (nonatomic, copy) NSString *fileName;
@property (nonatomic, copy) NSString *name;
@property (nonatomic, copy) NSString *about;
@property (nonatomic, copy) NSString *title;
@property (nonatomic, copy) NSString *body;
@property (nonatomic, copy) NSArray *labels;
@property (nonatomic, copy) NSArray *assignees;
@property (nonatomic, copy) NSArray *fields;

@property (nonatomic, readonly) BOOL isForm;

+ (instancetype)templateWithFileName:(NSString *)fileName contents:(NSString *)contents;

@end

@interface GHIssueContactLink : NSObject

@property (nonatomic, copy) NSString *name;
@property (nonatomic, copy) NSString *about;
@property (nonatomic, strong) NSURL *url;

@end

@interface GHIssueTemplateSet : NSObject

@property (nonatomic, copy) NSArray *templates;
@property (nonatomic, copy) NSArray *contactLinks;
@property (nonatomic, assign) BOOL blankIssuesEnabled;
@property (nonatomic, strong) GHIssueTemplate *legacyTemplate;

@property (nonatomic, readonly) BOOL hasChoices;

+ (void)loadForOwner:(NSString *)owner
                repo:(NSString *)repo
          completion:(void (^)(GHIssueTemplateSet *templateSet, NSError *error))completion;

@end
