//
//  ExceptionHandler.m
//  PostHogExample
//
//  Created for NSException handling in Swift
//

#import "ExceptionHandler.h"

@implementation ExceptionHandler

+ (void)tryBlock:(void(^)(void))tryBlock 
           catch:(void(^)(NSException *exception))catchBlock {
    [self tryBlock:tryBlock catch:catchBlock finally:nil];
}

+ (void)tryBlock:(void(^)(void))tryBlock 
           catch:(void(^)(NSException *exception))catchBlock
         finally:(nullable void(^)(void))finallyBlock {
    @try {
        if (tryBlock) {
            tryBlock();
        }
    }
    @catch (NSException *exception) {
        if (catchBlock) {
            catchBlock(exception);
        }
    }
    @finally {
        if (finallyBlock) {
            finallyBlock();
        }
    }
}

+ (void)triggerSampleRangeException {
    // This will throw an NSRangeException
    NSArray *array = @[@"item1", @"item2", @"item3"];
    [array objectAtIndex:10]; // Index out of bounds
}

+ (void)triggerSampleInvalidArgumentException {
    // This will throw an NSInvalidArgumentException
    NSMutableArray *mutableArray = [[NSMutableArray alloc] init];
    [mutableArray insertObject:nil atIndex:0]; // Inserting nil object
}

+ (void)triggerSampleGenericException {
    // This will throw a custom NSException
    @throw [NSException exceptionWithName:@"CustomTestException"
                                   reason:@"This is a manually triggered exception for testing"
                                 userInfo:@{
                                     @"test_type": @"manual_trigger",
                                     @"timestamp": [NSDate date],
                                     @"source": @"ExceptionHandler.triggerSampleGenericException"
                                 }];
}

+ (void)triggerChainedException {
    // Start the chained exception scenario
    [self performDatabaseOperation];
}

// MARK: - Private Helper Methods for Exception Chaining

/// Simulates a high-level business operation that calls lower-level functions
+ (void)performDatabaseOperation {
    @try {
        [self connectToDatabase];
    }
    @catch (NSException *exception) {
        // Catch the lower-level exception and wrap it with business context
        NSException *businessException = [NSException exceptionWithName:@"DatabaseOperationException"
                                                                 reason:@"Failed to perform user data synchronization"
                                                               userInfo:@{
                                                                   @"operation": @"user_sync",
                                                                   @"retry_count": @3,
                                                                   @"timestamp": [NSDate date],
                                                                   NSUnderlyingErrorKey: exception // This creates the exception chain
                                                               }];
        @throw businessException;
    }
}

/// Simulates a database connection that calls even lower-level network functions
+ (void)connectToDatabase {
    @try {
        [self establishNetworkConnection];
    }
    @catch (NSException *exception) {
        // Catch the network exception and wrap it with database context
        NSException *dbException = [NSException exceptionWithName:@"DatabaseConnectionException"
                                                           reason:@"Unable to establish database connection"
                                                         userInfo:@{
                                                             @"database_host": @"db.example.com",
                                                             @"connection_timeout": @30,
                                                             @"retry_attempts": @2,
                                                             NSUnderlyingErrorKey: exception // Chain the network exception
                                                         }];
        @throw dbException;
    }
}

/// Simulates the lowest-level network operation that throws the original exception
+ (void)establishNetworkConnection {
    // This is the root cause - a network connectivity issue
    @throw [NSException exceptionWithName:@"NetworkException"
                                   reason:@"Connection refused by remote server"
                                 userInfo:@{
                                     @"error_code": @"ECONNREFUSED",
                                     @"host": @"api.example.com",
                                     @"port": @443,
                                     @"protocol": @"HTTPS",
                                     @"timestamp": [NSDate date]
                                 }];
}

// MARK: - Crash Triggers for Testing

+ (void)triggerUncaughtNSException {
    @throw [NSException exceptionWithName:@"UncaughtTestException"
                                   reason:@"This is an intentionally uncaught exception for crash testing"
                                 userInfo:@{
                                     @"test_type": @"uncaught_exception",
                                     @"timestamp": [NSDate date]
                                 }];
}

+ (void)triggerNullPointerCrash {
    int *nullPointer = NULL;
    *nullPointer = 42;
}

+ (void)triggerAbortCrash {
    abort();
}

@end
