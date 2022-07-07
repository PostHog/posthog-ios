#import <Foundation/Foundation.h>
#import "PHGPayload.h"

NS_ASSUME_NONNULL_BEGIN


@interface PHGGroupPayload : PHGPayload

@property (nonatomic, readonly) NSString *groupType;

@property (nonatomic, readonly) NSString *groupKey;

@property (nonatomic, readonly, nullable) NSDictionary *properties;

- (instancetype)initWithType:(NSString *_Nonnull)groupType
                  groupKey:(NSString *_Nonnull)groupKey
                  properties:(NSDictionary *_Nullable)properties;

@end

NS_ASSUME_NONNULL_END
