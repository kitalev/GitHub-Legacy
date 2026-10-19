#import "GHTimelineRenderer.h"
#import <UIKit/UIKit.h>
#import "GHCompat.h"
#import "GHThemeManager.h"
#import "GHLocalization.h"
#import "GHMarkdownRenderer.h"
#import "GHIconRenderer.h"

@implementation GHTimelineRenderer

- (id)initWithOwnerLogin:(NSString *)ownerLogin repoName:(NSString *)repoName {
    self = [super init];
    if (self) {
        _ownerLogin = [ownerLogin copy];
        _repoName = [repoName copy];
    }
    return self;
}

#pragma mark - Helpers

- (NSString *)stringIn:(NSDictionary *)dict forKey:(NSString *)key {
    id value = [dict isKindOfClass:[NSDictionary class]] ? [dict objectForKey:key] : nil;
    return [value isKindOfClass:[NSString class]] ? value : nil;
}

- (NSDictionary *)dictIn:(NSDictionary *)dict forKey:(NSString *)key {
    id value = [dict isKindOfClass:[NSDictionary class]] ? [dict objectForKey:key] : nil;
    return [value isKindOfClass:[NSDictionary class]] ? value : nil;
}

- (NSNumber *)numberIn:(NSDictionary *)dict forKey:(NSString *)key {
    id value = [dict isKindOfClass:[NSDictionary class]] ? [dict objectForKey:key] : nil;
    return [value isKindOfClass:[NSNumber class]] ? value : @0;
}

- (NSString *)escape:(NSString *)text {
    return [GHMarkdownRenderer escapeHTML:text ?: @""];
}

- (NSString *)escapeAttribute:(NSString *)text {
    return [GHMarkdownRenderer escapeHTMLAttribute:text ?: @""];
}

- (BOOL)isDark {
    return [GHThemeManager sharedManager].darkModeEnabled;
}

- (NSString *)relativeTimeFromISOString:(NSString *)isoString {
    if (isoString.length == 0) return @"";
    NSDate *date = GHDateFromISO8601String(isoString);
    if (!date) return @"";

    NSTimeInterval seconds = MAX(0, -[date timeIntervalSinceNow]);
    NSInteger minutes = (NSInteger)(seconds / 60);
    NSInteger hours = minutes / 60;
    NSInteger days = hours / 24;
    BOOL russian = [[GHLocalization sharedManager].languageCode isEqualToString:@"ru"];

    if (minutes < 1) return russian ? @"сейчас" : @"now";
    if (minutes < 60) return [NSString stringWithFormat:russian ? @"%ld мин" : @"%ldm", (long)minutes];
    if (hours < 24) return [NSString stringWithFormat:russian ? @"%ld ч" : @"%ldh", (long)hours];
    if (days < 30) return [NSString stringWithFormat:russian ? @"%ld д" : @"%ldd", (long)days];
    if (days < 365) return [NSString stringWithFormat:russian ? @"%ld мес" : @"%ldmo", (long)(days / 30)];
    return [NSString stringWithFormat:russian ? @"%ld г" : @"%ldy", (long)(days / 365)];
}

- (NSString *)associationBadgeForValue:(NSString *)association {
    if ([association isEqualToString:@"OWNER"]) return GHL(@"Владелец");
    if ([association isEqualToString:@"MEMBER"]) return GHL(@"Участник");
    if ([association isEqualToString:@"COLLABORATOR"]) return GHL(@"Соавтор");
    if ([association isEqualToString:@"CONTRIBUTOR"]) return GHL(@"Контрибьютор");
    return nil;
}

#pragma mark - CSS

- (NSString *)styleCSS {
    BOOL dark = [self isDark];
    NSString *secondary = dark ? @"#9198a1" : @"#59636e";
    NSString *border = dark ? @"#30363d" : @"#d1d9e0";
    NSString *badgeBackground = dark ? @"rgba(255,255,255,0.10)" : @"rgba(0,0,0,0.06)";
    NSString *bandBackground = dark ? @"#0d1117" : @"#f6f8fa";
    NSString *link = dark ? @"#4493f8" : @"#0969da";
    NSString *branchBackground = dark ? @"rgba(56,139,253,0.15)" : @"rgba(9,105,218,0.10)";
    NSString *addition = dark ? @"#3fb950" : @"#1a7f37";
    NSString *deletion = dark ? @"#f85149" : @"#cf222e";

    NSMutableString *css = [NSMutableString stringWithString:@"<style>"];
    [css appendFormat:@".gh-repo-line{font-size:15px;color:%@;margin:4px 0 10px;}", secondary];
    [css appendString:@".gh-repo-avatar{width:22px;height:22px;border-radius:11px;vertical-align:middle;margin-right:8px;}"];
    [css appendString:@".gh-title{font-size:24px;line-height:1.25;font-weight:bold;margin:0 0 12px;}"];
    [css appendString:@".gh-state-row{margin:0 0 6px;line-height:2;}"];
    [css appendString:@".gh-state{display:inline-block;color:#fff;font-size:14px;font-weight:bold;padding:3px 12px;border-radius:14px;line-height:1.5;vertical-align:middle;}"];
    [css appendString:@".gh-state-row .issue-label{font-size:13px;vertical-align:middle;}"];
    [css appendFormat:@".gh-branch{display:inline-block;font-family:Menlo,Courier,monospace;font-size:13px;color:%@;background:%@;border-radius:6px;padding:3px 8px;margin-left:6px;vertical-align:middle;line-height:1.5;word-break:break-all;}", link, branchBackground];
    [css appendFormat:@".gh-post{margin:0 -16px;padding:16px 16px 18px;border-top:1px solid %@;}", border];
    [css appendString:@".gh-post-head{display:table;width:100%;margin-bottom:12px;}"];
    [css appendString:@".gh-post-avatar{display:table-cell;width:48px;vertical-align:middle;}"];
    [css appendString:@".gh-post-avatar img{width:40px;height:40px;border-radius:20px;display:block;}"];
    [css appendString:@".gh-post-meta{display:table-cell;vertical-align:middle;}"];
    [css appendString:@".gh-post-author{font-weight:bold;font-size:16px;}"];
    [css appendFormat:@".gh-post-time{color:%@;font-size:15px;}", secondary];
    [css appendFormat:@".gh-badge{display:inline-block;font-size:12px;color:%@;background:%@;border-radius:10px;padding:1px 9px;margin-top:3px;}", secondary, badgeBackground];
    [css appendString:@".gh-post-body p:first-child{margin-top:0;}.gh-post-body p:last-child{margin-bottom:0;}"];
    [css appendFormat:@".gh-empty{color:%@;font-style:italic;}", secondary];
    [css appendFormat:@".gh-event{margin:0 -16px;padding:12px 16px;border-top:1px solid %@;background:%@;display:table;width:100%%;box-sizing:border-box;}", border, bandBackground];
    [css appendString:@".gh-event-icon,.gh-row-icon{display:table-cell;width:36px;vertical-align:middle;}"];
    [css appendFormat:@".gh-event-icon span,.gh-row-icon span{display:block;width:26px;height:26px;border-radius:13px;text-align:center;line-height:26px;font-size:13px;font-weight:bold;color:%@;background:%@;}", secondary, badgeBackground];
    [css appendFormat:@".gh-event-text{display:table-cell;vertical-align:middle;font-size:14px;color:%@;}", secondary];
    [css appendString:@".gh-event-text .gh-actor{font-weight:bold;}"];
    [css appendFormat:@".gh-event-text a,.gh-row-text a{color:%@;text-decoration:none;}", link];
    [css appendString:@".gh-event-text .issue-label{margin:0 2px;}"];
    [css appendFormat:@".gh-event-time{color:%@;}", secondary];
    [css appendString:@".gh-commit{font-family:Menlo,Courier,monospace;font-size:13px;}"];
    [css appendFormat:@".gh-review-body{margin:0 -16px;padding:0 16px 14px 52px;background:%@;font-size:14px;}", bandBackground];
    [css appendFormat:@".gh-section{margin:0 -16px;padding:20px 16px 10px;border-top:1px solid %@;background:%@;font-size:17px;font-weight:bold;}", border, bandBackground];
    [css appendFormat:@".gh-row{margin:0 -16px;padding:12px 16px;border-top:1px solid %@;display:table;width:100%%;box-sizing:border-box;}", border];
    [css appendString:@".gh-row-text{display:table-cell;vertical-align:middle;font-size:16px;}"];
    [css appendFormat:@".gh-row-sub{display:block;color:%@;font-size:14px;margin-top:2px;}", secondary];
    [css appendFormat:@".gh-row-trailing{display:table-cell;vertical-align:middle;text-align:right;white-space:nowrap;font-size:15px;color:%@;padding-left:8px;}", secondary];
    [css appendFormat:@".gh-add{color:%@;}.gh-del{color:%@;}", addition, deletion];
    [css appendFormat:@".gh-error{color:%@;font-size:14px;margin:0 -16px;padding:12px 16px;border-top:1px solid %@;}", deletion, border];
    [css appendString:@"</style>"];
    return css;
}

#pragma mark - Header

- (NSString *)repoLineHTMLWithNumber:(NSNumber *)number {
    if (self.ownerLogin.length == 0 || self.repoName.length == 0) return @"";
    NSString *ownerAvatar = [NSString stringWithFormat:@"https://github.com/%@.png?size=44", self.ownerLogin];
    return [NSString stringWithFormat:@"<div class=\"gh-repo-line\"><img class=\"gh-repo-avatar\" src=\"%@\"/>%@ / %@ #%@</div>",
            [self escapeAttribute:ownerAvatar], [self escape:self.ownerLogin], [self escape:self.repoName], number ?: @0];
}

- (NSString *)titleHTML:(NSString *)title {
    return [NSString stringWithFormat:@"<h1 class=\"gh-title\">%@</h1>", [self escape:title]];
}

- (NSString *)stateRowHTMLWithLabel:(NSString *)label color:(NSString *)color extraHTML:(NSString *)extraHTML {
    return [NSString stringWithFormat:@"<div class=\"gh-state-row\"><span class=\"gh-state\" style=\"background:%@;\">%@</span>%@</div>",
            color, [self escape:label], extraHTML ?: @""];
}

- (BOOL)isValidHexColor:(NSString *)hex {
    if (hex.length != 6) return NO;
    NSCharacterSet *nonHex = [[NSCharacterSet characterSetWithCharactersInString:@"0123456789abcdefABCDEF"] invertedSet];
    return [hex rangeOfCharacterFromSet:nonHex].location == NSNotFound;
}

- (NSString *)labelSpanForLabel:(NSDictionary *)label {
    NSString *name = [self stringIn:label forKey:@"name"];
    if (name.length == 0) return @"";
    NSString *colorHex = [self stringIn:label forKey:@"color"] ?: @"ededed";
    if (![self isValidHexColor:colorHex]) colorHex = @"ededed";
    UIColor *background = [GHIconRenderer colorFromHexString:colorHex] ?: [UIColor colorWithWhite:0.93 alpha:1.0];
    BOOL blackText = [[GHIconRenderer readableTextColorOverColor:background] isEqual:[UIColor blackColor]];
    return [NSString stringWithFormat:@"<span class=\"issue-label\" style=\"background:#%@;color:%@;\">%@</span>",
            colorHex, blackText ? @"#000000" : @"#ffffff", [self escape:name]];
}

- (NSString *)labelsHTML:(NSArray *)labels {
    if (![labels isKindOfClass:[NSArray class]] || labels.count == 0) return @"";
    NSMutableString *html = [NSMutableString stringWithString:@"<span class=\"issue-labels\"> "];
    for (NSDictionary *label in labels) {
        if (![label isKindOfClass:[NSDictionary class]]) continue;
        [html appendString:[self labelSpanForLabel:label]];
    }
    [html appendString:@"</span>"];
    return html;
}

- (NSString *)branchHTML:(NSString *)branch {
    if (branch.length == 0) return @"";
    return [NSString stringWithFormat:@"<span class=\"gh-branch\">%@</span>", [self escape:branch]];
}

#pragma mark - Blocks

- (NSString *)postHTMLWithUser:(NSDictionary *)user
                     createdAt:(NSString *)createdAt
                   association:(NSString *)association
                          body:(NSString *)body {
    NSString *login = [self stringIn:user forKey:@"login"] ?: @"ghost";
    NSString *avatarURL = [self stringIn:user forKey:@"avatar_url"];
    NSString *when = [self relativeTimeFromISOString:createdAt];
    NSString *badge = [self associationBadgeForValue:association];

    NSMutableString *html = [NSMutableString stringWithString:@"<div class=\"gh-post\"><div class=\"gh-post-head\"><div class=\"gh-post-avatar\">"];
    if (avatarURL.length > 0) [html appendFormat:@"<img src=\"%@\"/>", [self escapeAttribute:avatarURL]];
    [html appendString:@"</div><div class=\"gh-post-meta\">"];
    [html appendFormat:@"<span class=\"gh-post-author\">%@</span>", [self escape:login]];
    if (when.length > 0) [html appendFormat:@"<span class=\"gh-post-time\"> · %@</span>", [self escape:when]];
    if (badge.length > 0) [html appendFormat:@"<br/><span class=\"gh-badge\">%@</span>", [self escape:badge]];
    [html appendString:@"</div></div><div class=\"gh-post-body\">"];
    if (body.length > 0) {
        [html appendString:[GHMarkdownRenderer downscaleRemoteImagesInHTML:[GHMarkdownRenderer bodyHTMLFromMarkdown:body repoOwner:self.ownerLogin repoName:self.repoName]]];
    } else {
        [html appendFormat:@"<p class=\"gh-empty\">%@</p>", [self escape:GHL(@"Описание не добавлено.")]];
    }
    [html appendString:@"</div></div>"];
    return html;
}

- (NSString *)glyphSpan:(NSString *)glyph color:(NSString *)color background:(NSString *)background {
    NSString *style = color.length > 0 ? [NSString stringWithFormat:@" style=\"color:%@;background:%@;\"", color, background] : @"";
    return [NSString stringWithFormat:@"<span%@>%@</span>", style, glyph];
}

- (NSString *)eventHTMLWithGlyph:(NSString *)glyph
                      glyphColor:(NSString *)glyphColor
                 glyphBackground:(NSString *)glyphBackground
                           actor:(NSString *)actor
                        textHTML:(NSString *)textHTML
                       createdAt:(NSString *)createdAt {
    NSString *when = [self relativeTimeFromISOString:createdAt];
    NSMutableString *html = [NSMutableString stringWithFormat:
        @"<div class=\"gh-event\"><div class=\"gh-event-icon\">%@</div><div class=\"gh-event-text\">",
        [self glyphSpan:glyph color:glyphColor background:glyphBackground]];
    if (actor.length > 0) [html appendFormat:@"<span class=\"gh-actor\">%@</span> ", [self escape:actor]];
    [html appendString:textHTML ?: @""];
    if (when.length > 0) [html appendFormat:@" <span class=\"gh-event-time\">· %@</span>", [self escape:when]];
    [html appendString:@"</div></div>"];
    return html;
}

- (NSString *)sectionHeaderHTML:(NSString *)title {
    return [NSString stringWithFormat:@"<div class=\"gh-section\">%@</div>", [self escape:title]];
}

- (NSString *)rowHTMLWithGlyph:(NSString *)glyph
                    glyphColor:(NSString *)glyphColor
               glyphBackground:(NSString *)glyphBackground
                     titleHTML:(NSString *)titleHTML
                  subtitleHTML:(NSString *)subtitleHTML
                  trailingHTML:(NSString *)trailingHTML {
    NSMutableString *html = [NSMutableString stringWithFormat:
        @"<div class=\"gh-row\"><div class=\"gh-row-icon\">%@</div><div class=\"gh-row-text\">%@",
        [self glyphSpan:glyph color:glyphColor background:glyphBackground], titleHTML ?: @""];
    if (subtitleHTML.length > 0) [html appendFormat:@"<span class=\"gh-row-sub\">%@</span>", subtitleHTML];
    [html appendString:@"</div>"];
    if (trailingHTML.length > 0) [html appendFormat:@"<div class=\"gh-row-trailing\">%@</div>", trailingHTML];
    [html appendString:@"</div>"];
    return html;
}

- (NSString *)errorHTML:(NSString *)text {
    if (text.length == 0) return @"";
    return [NSString stringWithFormat:@"<div class=\"gh-error\">%@</div>", [self escape:text]];
}

- (NSString *)additionsHTML:(NSInteger)additions deletions:(NSInteger)deletions {
    return [NSString stringWithFormat:@"<span class=\"gh-add\">+%ld</span> <span class=\"gh-del\">−%ld</span>",
            (long)additions, (long)deletions];
}

#pragma mark - Timeline

- (NSString *)timelineItemHTML:(NSDictionary *)item {
    if (![item isKindOfClass:[NSDictionary class]]) return @"";

    NSString *event = [self stringIn:item forKey:@"event"];
    NSString *createdAt = [self stringIn:item forKey:@"created_at"];
    NSDictionary *actorDict = [self dictIn:item forKey:@"actor"] ?: [self dictIn:item forKey:@"user"];
    NSString *actor = [self stringIn:actorDict forKey:@"login"];

    if (event.length == 0 || [event isEqualToString:@"commented"]) {
        if (event.length == 0 && ![item objectForKey:@"body"]) return @"";
        return [self postHTMLWithUser:[self dictIn:item forKey:@"user"] ?: actorDict
                            createdAt:createdAt
                          association:[self stringIn:item forKey:@"author_association"]
                                 body:[self stringIn:item forKey:@"body"]];
    }

    if ([event isEqualToString:@"labeled"] || [event isEqualToString:@"unlabeled"]) {
        NSString *labelHTML = [self labelSpanForLabel:[self dictIn:item forKey:@"label"]];
        NSString *format = [event isEqualToString:@"labeled"] ? GHL(@"добавил(а) метку %@") : GHL(@"убрал(а) метку %@");
        return [self eventHTMLWithGlyph:@"#" glyphColor:nil glyphBackground:nil actor:actor
                               textHTML:[NSString stringWithFormat:format, labelHTML] createdAt:createdAt];
    }

    if ([event isEqualToString:@"closed"]) {
        if (self.isPullRequest) {
            return [self eventHTMLWithGlyph:@"✕" glyphColor:@"#fff" glyphBackground:@"#cf222e" actor:actor
                                   textHTML:GHL(@"закрыл(а) пул-реквест") createdAt:createdAt];
        }
        NSString *reason = [self stringIn:item forKey:@"state_reason"];
        if ([reason isEqualToString:@"not_planned"]) {
            return [self eventHTMLWithGlyph:@"⊘" glyphColor:@"#fff" glyphBackground:@"#59636e" actor:actor
                                   textHTML:GHL(@"закрыл(а) задачу как не планируемую") createdAt:createdAt];
        }
        if ([reason isEqualToString:@"duplicate"]) {
            return [self eventHTMLWithGlyph:@"⊘" glyphColor:@"#fff" glyphBackground:@"#59636e" actor:actor
                                   textHTML:GHL(@"закрыл(а) задачу как дубликат") createdAt:createdAt];
        }
        return [self eventHTMLWithGlyph:@"✓" glyphColor:@"#fff" glyphBackground:@"#8250df" actor:actor
                               textHTML:GHL(@"закрыл(а) задачу как выполненную") createdAt:createdAt];
    }

    if ([event isEqualToString:@"reopened"]) {
        return [self eventHTMLWithGlyph:@"●" glyphColor:@"#fff" glyphBackground:@"#1f883d" actor:actor
                               textHTML:(self.isPullRequest ? GHL(@"снова открыл(а) пул-реквест") : GHL(@"снова открыл(а) задачу"))
                              createdAt:createdAt];
    }

    if ([event isEqualToString:@"renamed"]) {
        NSDictionary *rename = [self dictIn:item forKey:@"rename"];
        NSString *text = [NSString stringWithFormat:GHL(@"изменил(а) заголовок: <s>%@</s> → <b>%@</b>"),
                          [self escape:[self stringIn:rename forKey:@"from"]], [self escape:[self stringIn:rename forKey:@"to"]]];
        return [self eventHTMLWithGlyph:@"✎" glyphColor:nil glyphBackground:nil actor:actor textHTML:text createdAt:createdAt];
    }

    if ([event isEqualToString:@"assigned"] || [event isEqualToString:@"unassigned"]) {
        NSString *assignee = [self stringIn:[self dictIn:item forKey:@"assignee"] forKey:@"login"];
        NSString *format = [event isEqualToString:@"assigned"] ? GHL(@"назначил(а) %@") : GHL(@"снял(а) назначение с %@");
        NSString *text = [NSString stringWithFormat:format, [NSString stringWithFormat:@"<b>%@</b>", [self escape:assignee]]];
        return [self eventHTMLWithGlyph:@"@" glyphColor:nil glyphBackground:nil actor:actor textHTML:text createdAt:createdAt];
    }

    if ([event isEqualToString:@"review_requested"]) {
        NSString *reviewer = [self stringIn:[self dictIn:item forKey:@"requested_reviewer"] forKey:@"login"]
                          ?: [self stringIn:[self dictIn:item forKey:@"requested_team"] forKey:@"name"];
        if (reviewer.length == 0) return @"";
        NSString *text = [NSString stringWithFormat:GHL(@"запросил(а) отзыв у %@"),
                          [NSString stringWithFormat:@"<b>%@</b>", [self escape:reviewer]]];
        return [self eventHTMLWithGlyph:@"○" glyphColor:nil glyphBackground:nil actor:actor textHTML:text createdAt:createdAt];
    }

    if ([event isEqualToString:@"cross-referenced"]) {
        NSDictionary *sourceIssue = [self dictIn:[self dictIn:item forKey:@"source"] forKey:@"issue"];
        NSString *title = [self stringIn:sourceIssue forKey:@"title"];
        NSString *url = [self stringIn:sourceIssue forKey:@"html_url"];
        if (title.length == 0 || url.length == 0) return @"";
        NSString *link = [NSString stringWithFormat:@"<a href=\"%@\">%@ #%@</a>",
                          [self escapeAttribute:url], [self escape:title], [self numberIn:sourceIssue forKey:@"number"]];
        return [self eventHTMLWithGlyph:@"↗" glyphColor:nil glyphBackground:nil actor:actor
                               textHTML:[NSString stringWithFormat:GHL(@"упомянул(а) задачу в %@"), link] createdAt:createdAt];
    }

    if ([event isEqualToString:@"committed"]) {
        NSString *sha = [self stringIn:item forKey:@"sha"];
        NSString *message = [[[self stringIn:item forKey:@"message"] componentsSeparatedByString:@"\n"] firstObject];
        NSDictionary *author = [self dictIn:item forKey:@"author"];
        NSString *authorName = [self stringIn:author forKey:@"name"];
        NSString *date = [self stringIn:author forKey:@"date"] ?: [self stringIn:[self dictIn:item forKey:@"committer"] forKey:@"date"];
        if (sha.length == 0) return @"";
        NSString *shortSha = sha.length > 7 ? [sha substringToIndex:7] : sha;
        NSString *url = [NSString stringWithFormat:@"https://github.com/%@/%@/commit/%@", self.ownerLogin, self.repoName, sha];
        NSString *text = [NSString stringWithFormat:@"<a class=\"gh-commit\" href=\"%@\">%@</a> %@",
                          [self escapeAttribute:url], [self escape:shortSha], [self escape:message]];
        return [self eventHTMLWithGlyph:@"◦" glyphColor:nil glyphBackground:nil actor:authorName textHTML:text createdAt:date];
    }

    if ([event isEqualToString:@"reviewed"]) {
        NSString *state = [[self stringIn:item forKey:@"state"] lowercaseString];
        NSString *submittedAt = [self stringIn:item forKey:@"submitted_at"];
        NSString *body = [self stringIn:item forKey:@"body"];
        NSString *glyph = @"○";
        NSString *color = nil;
        NSString *background = nil;
        NSString *text = GHL(@"оставил(а) отзыв");
        if ([state isEqualToString:@"approved"]) {
            glyph = @"✓"; color = @"#fff"; background = @"#1f883d";
            text = GHL(@"одобрил(а) изменения");
        } else if ([state isEqualToString:@"changes_requested"]) {
            glyph = @"±"; color = @"#fff"; background = @"#cf222e";
            text = GHL(@"запросил(а) изменения");
        } else if ([state isEqualToString:@"dismissed"]) {
            text = GHL(@"отзыв отклонён");
        }
        NSMutableString *html = [NSMutableString stringWithString:
            [self eventHTMLWithGlyph:glyph glyphColor:color glyphBackground:background actor:actor textHTML:text createdAt:submittedAt]];
        if (body.length > 0) {
            [html appendFormat:@"<div class=\"gh-review-body\">%@</div>",
                [GHMarkdownRenderer downscaleRemoteImagesInHTML:[GHMarkdownRenderer bodyHTMLFromMarkdown:body repoOwner:self.ownerLogin repoName:self.repoName]]];
        }
        return html;
    }

    if ([event isEqualToString:@"merged"]) {
        NSString *commitId = [self stringIn:item forKey:@"commit_id"];
        NSString *shortSha = commitId.length > 7 ? [commitId substringToIndex:7] : (commitId ?: @"");
        NSString *text = shortSha.length > 0
            ? [NSString stringWithFormat:GHL(@"слил(а) коммит %@"), [NSString stringWithFormat:@"<span class=\"gh-commit\">%@</span>", [self escape:shortSha]]]
            : GHL(@"слил(а) пул-реквест");
        return [self eventHTMLWithGlyph:@"⑂" glyphColor:@"#fff" glyphBackground:@"#8250df" actor:actor textHTML:text createdAt:createdAt];
    }

    if ([event isEqualToString:@"head_ref_deleted"]) {
        return [self eventHTMLWithGlyph:@"✕" glyphColor:nil glyphBackground:nil actor:actor
                               textHTML:GHL(@"удалил(а) ветку") createdAt:createdAt];
    }

    if ([event isEqualToString:@"ready_for_review"]) {
        return [self eventHTMLWithGlyph:@"○" glyphColor:nil glyphBackground:nil actor:actor
                               textHTML:GHL(@"отметил(а) как готовый к ревью") createdAt:createdAt];
    }

    if ([event isEqualToString:@"convert_to_draft"]) {
        return [self eventHTMLWithGlyph:@"○" glyphColor:nil glyphBackground:nil actor:actor
                               textHTML:GHL(@"перевёл(а) в черновик") createdAt:createdAt];
    }

    return @"";
}

@end
