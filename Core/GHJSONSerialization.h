#import <Foundation/Foundation.h>

@interface GHJSONSerialization : NSObject

+ (BOOL)isValidJSONObject:(id)obj;
+ (id)JSONObjectWithData:(NSData *)data options:(NSJSONReadingOptions)opt error:(NSError **)error;
+ (NSData *)dataWithJSONObject:(id)obj options:(NSJSONWritingOptions)opt error:(NSError **)error;

@end
