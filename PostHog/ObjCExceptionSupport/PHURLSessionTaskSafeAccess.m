#import "PHURLSessionTaskSafeAccess.h"

@implementation PHURLSessionTaskSafeAccess

+ (nullable NSURLRequest *)currentRequestFromTask:(NSURLSessionTask *)task {
    @try {
        return task.currentRequest;
    } @catch (__unused NSException *exception) {
        return nil;
    }
}

+ (BOOL)setCurrentRequest:(NSURLRequest *)request onTask:(NSURLSessionTask *)task key:(NSString *)key {
    @try {
        [task setValue:request forKey:key];
        return YES;
    } @catch (__unused NSException *exception) {
        return NO;
    }
}

@end
