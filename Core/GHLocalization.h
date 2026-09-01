#import <Foundation/Foundation.h>

extern NSString * const kGHLanguageDidChangeNotification;

@interface GHLocalization : NSObject

+ (instancetype)sharedManager;

@property (nonatomic, copy) NSString *languageCode;

@end

FOUNDATION_EXPORT NSString *GHL(NSString *russianText);
