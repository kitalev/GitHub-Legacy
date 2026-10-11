#import "GHIssueTemplate.h"
#import "GHYAMLParser.h"
#import "GHAPIClient.h"

static NSString * const kGHIssueNoResponse = @"_No response_";

static NSDictionary *GHIssueDict(id value) {
    return [value isKindOfClass:[NSDictionary class]] ? value : nil;
}

static NSString *GHIssueTrimmed(NSString *string) {
    return [string stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
}

static NSString *GHIssueYAMLText(id value) {
    NSString *string = GHYAMLString(value);
    return string.length > 0 ? string : nil;
}

#pragma mark - GHIssueFormField

@implementation GHIssueFormField

+ (instancetype)fieldWithDictionary:(NSDictionary *)dictionary {
    if (![dictionary isKindOfClass:[NSDictionary class]]) return nil;

    NSString *typeName = [GHIssueYAMLText(dictionary[@"type"]) lowercaseString] ?: @"";
    NSDictionary *attributes = GHIssueDict(dictionary[@"attributes"]) ?: @{};
    NSDictionary *validations = GHIssueDict(dictionary[@"validations"]) ?: @{};

    GHIssueFormField *field = [[GHIssueFormField alloc] init];
    field.defaultIndex = -1;
    field.label = GHIssueTrimmed(GHIssueYAMLText(attributes[@"label"]) ?: @"");
    field.fieldDescription = GHIssueTrimmed(GHIssueYAMLText(attributes[@"description"]) ?: @"");
    field.placeholder = GHIssueYAMLText(attributes[@"placeholder"]);
    field.required = GHYAMLBool(validations[@"required"], NO);

    if ([typeName isEqualToString:@"markdown"]) {
        field.type = GHIssueFormFieldTypeMarkdown;
        field.value = GHIssueTrimmed(GHIssueYAMLText(attributes[@"value"]) ?: @"");
        return field.value.length > 0 ? field : nil;
    }

    if ([typeName isEqualToString:@"input"] || [typeName isEqualToString:@"textarea"]) {
        field.type = [typeName isEqualToString:@"input"] ? GHIssueFormFieldTypeInput : GHIssueFormFieldTypeTextarea;
        field.value = GHIssueYAMLText(attributes[@"value"]);
        if (field.type == GHIssueFormFieldTypeTextarea) field.render = GHIssueTrimmed(GHIssueYAMLText(attributes[@"render"]) ?: @"");
    } else if ([typeName isEqualToString:@"dropdown"]) {
        field.type = GHIssueFormFieldTypeDropdown;
        field.options = GHYAMLStringList([attributes[@"options"] isKindOfClass:[NSArray class]] ? attributes[@"options"] : nil);
        field.multiple = GHYAMLBool(attributes[@"multiple"], NO);
        NSString *defaultText = GHIssueYAMLText(attributes[@"default"]);
        if (defaultText.length > 0) {
            NSInteger index = [defaultText integerValue];
            if (index >= 0 && index < (NSInteger)field.options.count) field.defaultIndex = index;
        }
        if (field.options.count == 0) return nil;
    } else if ([typeName isEqualToString:@"checkboxes"]) {
        field.type = GHIssueFormFieldTypeCheckboxes;
        NSMutableArray *labels = [NSMutableArray array];
        NSMutableArray *requiredIndexes = [NSMutableArray array];
        id rawOptions = attributes[@"options"];
        for (id option in [rawOptions isKindOfClass:[NSArray class]] ? rawOptions : @[]) {
            NSDictionary *optionDict = GHIssueDict(option);
            NSString *optionLabel = optionDict ? GHIssueYAMLText(optionDict[@"label"]) : GHIssueYAMLText(option);
            if (optionLabel.length == 0) continue;
            if (optionDict && GHYAMLBool(optionDict[@"required"], NO)) [requiredIndexes addObject:@(labels.count)];
            [labels addObject:GHIssueTrimmed(optionLabel)];
        }
        field.options = labels;
        field.requiredOptionIndexes = requiredIndexes;
        if (field.options.count == 0) return nil;
    } else {
        return nil;
    }

    return field.label.length > 0 ? field : nil;
}

- (id)initialValue {
    switch (self.type) {
        case GHIssueFormFieldTypeInput:
        case GHIssueFormFieldTypeTextarea:
            return self.value ?: @"";
        case GHIssueFormFieldTypeDropdown: {
            NSMutableIndexSet *selection = [NSMutableIndexSet indexSet];
            if (self.defaultIndex >= 0) [selection addIndex:(NSUInteger)self.defaultIndex];
            return selection;
        }
        case GHIssueFormFieldTypeCheckboxes:
            return [NSMutableIndexSet indexSet];
        default:
            return nil;
    }
}

- (BOOL)isSatisfiedByValue:(id)value {
    switch (self.type) {
        case GHIssueFormFieldTypeInput:
        case GHIssueFormFieldTypeTextarea:
            return !self.required || GHIssueTrimmed([value isKindOfClass:[NSString class]] ? value : @"").length > 0;
        case GHIssueFormFieldTypeDropdown:
            return !self.required || ([value isKindOfClass:[NSIndexSet class]] && [value count] > 0);
        case GHIssueFormFieldTypeCheckboxes:
            for (NSNumber *index in self.requiredOptionIndexes) {
                if (![value isKindOfClass:[NSIndexSet class]] || ![value containsIndex:index.unsignedIntegerValue]) return NO;
            }
            return YES;
        default:
            return YES;
    }
}

- (NSString *)bodySectionWithValue:(id)value {
    NSString *content = nil;
    switch (self.type) {
        case GHIssueFormFieldTypeInput:
        case GHIssueFormFieldTypeTextarea: {
            NSString *text = GHIssueTrimmed([value isKindOfClass:[NSString class]] ? value : @"");
            if (text.length == 0) {
                content = kGHIssueNoResponse;
            } else if (self.render.length > 0) {
                content = [NSString stringWithFormat:@"```%@\n%@\n```", self.render, text];
            } else {
                content = text;
            }
            break;
        }
        case GHIssueFormFieldTypeDropdown: {
            NSMutableArray *selected = [NSMutableArray array];
            if ([value isKindOfClass:[NSIndexSet class]]) {
                [value enumerateIndexesUsingBlock:^(NSUInteger index, BOOL *stop) {
                    if (index < self.options.count) [selected addObject:self.options[index]];
                }];
            }
            content = selected.count > 0 ? [selected componentsJoinedByString:@", "] : kGHIssueNoResponse;
            break;
        }
        case GHIssueFormFieldTypeCheckboxes: {
            NSMutableArray *lines = [NSMutableArray array];
            for (NSUInteger i = 0; i < self.options.count; i++) {
                BOOL checked = [value isKindOfClass:[NSIndexSet class]] && [value containsIndex:i];
                [lines addObject:[NSString stringWithFormat:@"- [%@] %@", checked ? @"X" : @" ", self.options[i]]];
            }
            content = [lines componentsJoinedByString:@"\n"];
            break;
        }
        default:
            return nil;
    }
    return [NSString stringWithFormat:@"### %@\n\n%@", self.label, content];
}

@end

#pragma mark - GHIssueTemplate

@implementation GHIssueTemplate

- (BOOL)isForm {
    return self.fields != nil;
}

+ (NSString *)frontMatterFromContents:(NSString *)contents body:(NSString **)body {
    NSString *normalized = [contents stringByReplacingOccurrencesOfString:@"\r\n" withString:@"\n"];
    if ([normalized hasPrefix:@"﻿"]) normalized = [normalized substringFromIndex:1];
    if (body != NULL) *body = normalized;

    NSArray *lines = [normalized componentsSeparatedByString:@"\n"];
    if (lines.count < 2 || ![GHIssueTrimmed(lines[0]) isEqualToString:@"---"]) return nil;

    for (NSUInteger i = 1; i < lines.count; i++) {
        NSString *line = GHIssueTrimmed(lines[i]);
        if (![line isEqualToString:@"---"] && ![line isEqualToString:@"..."]) continue;

        NSString *frontMatter = [[lines subarrayWithRange:NSMakeRange(1, i - 1)] componentsJoinedByString:@"\n"];
        NSString *rest = [[lines subarrayWithRange:NSMakeRange(i + 1, lines.count - i - 1)] componentsJoinedByString:@"\n"];
        while ([rest hasPrefix:@"\n"]) rest = [rest substringFromIndex:1];
        if (body != NULL) *body = rest;
        return frontMatter;
    }
    return nil;
}

+ (instancetype)templateWithFileName:(NSString *)fileName contents:(NSString *)contents {
    NSString *extension = [[fileName pathExtension] lowercaseString];
    GHIssueTemplate *template = [[GHIssueTemplate alloc] init];
    template.fileName = fileName;

    NSDictionary *metadata = nil;
    if ([extension isEqualToString:@"yml"] || [extension isEqualToString:@"yaml"]) {
        metadata = GHIssueDict([GHYAMLParser objectFromString:contents]);
        id rawBody = metadata[@"body"];
        if (![rawBody isKindOfClass:[NSArray class]]) return nil;

        NSMutableArray *fields = [NSMutableArray array];
        for (id entry in rawBody) {
            GHIssueFormField *field = [GHIssueFormField fieldWithDictionary:GHIssueDict(entry)];
            if (field) [fields addObject:field];
        }
        template.fields = fields;
        template.about = GHIssueYAMLText(metadata[@"description"]);
    } else {
        NSString *body = nil;
        NSString *frontMatter = [self frontMatterFromContents:contents ?: @"" body:&body];
        metadata = frontMatter.length > 0 ? GHIssueDict([GHYAMLParser objectFromString:frontMatter]) : nil;
        template.body = body;
        template.about = GHIssueYAMLText(metadata[@"about"]);
    }

    template.name = GHIssueTrimmed(GHIssueYAMLText(metadata[@"name"]) ?: @"");
    if (template.name.length == 0) template.name = [fileName stringByDeletingPathExtension];
    template.about = GHIssueTrimmed(template.about ?: @"");
    template.title = GHIssueYAMLText(metadata[@"title"]);
    template.labels = GHYAMLStringList(metadata[@"labels"]);
    template.assignees = GHYAMLStringList(metadata[@"assignees"]);
    return template;
}

@end

#pragma mark - GHIssueContactLink

@implementation GHIssueContactLink
@end

#pragma mark - GHIssueTemplateSet

typedef void (^GHIssueTemplateSetCompletion)(GHIssueTemplateSet *templateSet, NSError *error);

@implementation GHIssueTemplateSet

- (id)init {
    self = [super init];
    if (self) {
        _templates = @[];
        _contactLinks = @[];
        _blankIssuesEnabled = YES;
    }
    return self;
}

- (BOOL)hasChoices {
    return self.templates.count > 0 || self.contactLinks.count > 0;
}

- (void)applyConfigText:(NSString *)configText {
    NSDictionary *config = GHIssueDict([GHYAMLParser objectFromString:configText]);
    if (config == nil) return;

    self.blankIssuesEnabled = GHYAMLBool(config[@"blank_issues_enabled"], YES);

    NSMutableArray *links = [NSMutableArray array];
    id rawLinks = config[@"contact_links"];
    for (id entry in [rawLinks isKindOfClass:[NSArray class]] ? rawLinks : @[]) {
        NSDictionary *linkDict = GHIssueDict(entry);
        NSString *name = GHIssueTrimmed(GHIssueYAMLText(linkDict[@"name"]) ?: @"");
        NSString *urlString = GHIssueTrimmed(GHIssueYAMLText(linkDict[@"url"]) ?: @"");
        NSURL *url = urlString.length > 0 ? [NSURL URLWithString:urlString] : nil;
        if (name.length == 0 || url == nil) continue;

        GHIssueContactLink *link = [[GHIssueContactLink alloc] init];
        link.name = name;
        link.about = GHIssueTrimmed(GHIssueYAMLText(linkDict[@"about"]) ?: @"");
        link.url = url;
        [links addObject:link];
    }
    self.contactLinks = links;
}

+ (void)loadForOwner:(NSString *)owner repo:(NSString *)repo completion:(GHIssueTemplateSetCompletion)completion {
    NSMutableArray *sources = [NSMutableArray arrayWithObject:@[owner ?: @"", repo ?: @""]];
    if (![[repo lowercaseString] isEqualToString:@".github"]) [sources addObject:@[owner ?: @"", @".github"]];

    NSMutableArray *probes = [NSMutableArray array];
    for (NSArray *source in sources) {
        for (NSString *directory in @[@".github", @"", @"docs"]) {
            [probes addObject:@[source[0], source[1], directory]];
        }
    }
    [self runProbes:probes index:0 completion:completion];
}

+ (void)runProbes:(NSArray *)probes index:(NSUInteger)index completion:(GHIssueTemplateSetCompletion)completion {
    if (index >= probes.count) {
        if (completion) completion([[GHIssueTemplateSet alloc] init], nil);
        return;
    }

    NSArray *probe = probes[index];
    NSString *owner = probe[0];
    NSString *repo = probe[1];
    NSString *directory = probe[2];

    [[GHAPIClient sharedClient] fileContentsForOwner:owner repo:repo path:directory completion:^(id jsonObject, NSError *error) {
        if (error && index == 0 && error.code != 404) {
            if (completion) completion(nil, error);
            return;
        }

        NSDictionary *templateDirectory = nil;
        NSDictionary *legacyFile = nil;
        for (id entry in [jsonObject isKindOfClass:[NSArray class]] ? jsonObject : @[]) {
            NSDictionary *item = GHIssueDict(entry);
            NSString *name = [GHIssueYAMLText(item[@"name"]) lowercaseString];
            NSString *type = GHIssueYAMLText(item[@"type"]);
            if ([type isEqualToString:@"dir"] && [name isEqualToString:@"issue_template"] && ![directory isEqualToString:@"docs"]) {
                templateDirectory = item;
            } else if ([type isEqualToString:@"file"] && [name isEqualToString:@"issue_template.md"]) {
                legacyFile = item;
            }
        }

        if (templateDirectory) {
            [self loadTemplateDirectoryForOwner:owner repo:repo path:GHIssueYAMLText(templateDirectory[@"path"]) completion:completion];
        } else if (legacyFile) {
            [self loadLegacyTemplateForOwner:owner repo:repo entry:legacyFile completion:completion];
        } else {
            [self runProbes:probes index:index + 1 completion:completion];
        }
    }];
}

+ (void)loadLegacyTemplateForOwner:(NSString *)owner
                              repo:(NSString *)repo
                             entry:(NSDictionary *)entry
                        completion:(GHIssueTemplateSetCompletion)completion {
    [[GHAPIClient sharedClient] rawFileForOwner:owner repo:repo path:GHIssueYAMLText(entry[@"path"]) completion:^(NSString *text, NSError *error) {
        if (error) {
            if (completion) completion(nil, error);
            return;
        }
        GHIssueTemplateSet *templateSet = [[GHIssueTemplateSet alloc] init];
        GHIssueTemplate *legacy = [GHIssueTemplate templateWithFileName:GHIssueYAMLText(entry[@"name"]) contents:text];
        legacy.name = nil;
        templateSet.legacyTemplate = legacy;
        if (completion) completion(templateSet, nil);
    }];
}

+ (void)loadTemplateDirectoryForOwner:(NSString *)owner
                                 repo:(NSString *)repo
                                 path:(NSString *)path
                           completion:(GHIssueTemplateSetCompletion)completion {
    [[GHAPIClient sharedClient] fileContentsForOwner:owner repo:repo path:path completion:^(id jsonObject, NSError *error) {
        if (error) {
            if (completion) completion(nil, error);
            return;
        }

        NSMutableArray *files = [NSMutableArray array];
        for (id entry in [jsonObject isKindOfClass:[NSArray class]] ? jsonObject : @[]) {
            NSDictionary *item = GHIssueDict(entry);
            NSString *extension = [[GHIssueYAMLText(item[@"name"]) pathExtension] lowercaseString];
            if (![GHIssueYAMLText(item[@"type"]) isEqualToString:@"file"]) continue;
            if (![@[@"md", @"yml", @"yaml"] containsObject:extension ?: @""]) continue;
            [files addObject:item];
        }

        GHIssueTemplateSet *templateSet = [[GHIssueTemplateSet alloc] init];
        if (files.count == 0) {
            if (completion) completion(templateSet, nil);
            return;
        }

        NSMutableArray *templates = [NSMutableArray array];
        __block NSString *configText = nil;
        __block NSUInteger remaining = files.count;

        void (^finish)(void) = ^{
            [templates sortUsingComparator:^NSComparisonResult(GHIssueTemplate *a, GHIssueTemplate *b) {
                return [a.fileName caseInsensitiveCompare:b.fileName];
            }];
            templateSet.templates = templates;
            if (configText.length > 0) [templateSet applyConfigText:configText];
            if (completion) completion(templateSet, nil);
        };

        for (NSDictionary *file in files) {
            NSString *name = GHIssueYAMLText(file[@"name"]);
            NSString *lowerName = [name lowercaseString];
            BOOL isConfig = [lowerName isEqualToString:@"config.yml"] || [lowerName isEqualToString:@"config.yaml"];

            [[GHAPIClient sharedClient] rawFileForOwner:owner repo:repo path:GHIssueYAMLText(file[@"path"]) completion:^(NSString *text, NSError *fileError) {
                if (text.length > 0) {
                    if (isConfig) {
                        configText = text;
                    } else {
                        GHIssueTemplate *template = [GHIssueTemplate templateWithFileName:name contents:text];
                        if (template) [templates addObject:template];
                    }
                }
                remaining--;
                if (remaining == 0) finish();
            }];
        }
    }];
}

@end
