#import <Foundation/Foundation.h>

@interface GHYAMLParser : NSObject

+ (id)objectFromString:(NSString *)string;

@end

FOUNDATION_EXTERN NSString *GHYAMLString(id value);
FOUNDATION_EXTERN BOOL GHYAMLBool(id value, BOOL defaultValue);
FOUNDATION_EXTERN NSArray *GHYAMLStringList(id value);
