#import "PHGGroupPayload.h"


@implementation PHGGroupPayload

- (instancetype)initWithType:(NSString *_Nonnull)groupType
                  groupKey:(NSString *_Nonnull)groupKey
                  properties:(NSDictionary *_Nullable)properties;
{
    if (self = [super init]) {
        _groupType = [groupType copy];
        _groupKey = [groupKey copy];
        _properties = [properties copy];
    }
    return self;
}

@end
