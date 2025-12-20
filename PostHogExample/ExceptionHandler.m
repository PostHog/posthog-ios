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

+ (void)triggerNullPointerCrash {
    // Trigger a null pointer dereference (EXC_BAD_ACCESS / KERN_INVALID_ADDRESS)
    int *nullPointer = NULL;
    *nullPointer = 42;
}

+ (void)triggerStackOverflowCrash {
    // Trigger stack overflow via infinite recursion (EXC_BAD_ACCESS / KERN_PROTECTION_FAILURE)
    [self triggerStackOverflowCrash];
}

+ (void)triggerAbortCrash {
    // Trigger SIGABRT
    abort();
}

+ (void)triggerIllegalInstructionCrash {
    // Trigger SIGILL / EXC_BAD_INSTRUCTION by executing invalid instruction
    // This uses inline assembly to execute an undefined instruction
#if defined(__arm64__)
    __asm__ volatile(".word 0x00000000"); // Undefined instruction on ARM64
#elif defined(__x86_64__)
    __asm__ volatile("ud2"); // Undefined instruction on x86_64
#else
    // Fallback: raise SIGILL directly
    raise(SIGILL);
#endif
}

+ (void)triggerUncaughtNSException {
    // Trigger an uncaught NSException (will be caught by PLCrashReporter)
    @throw [NSException exceptionWithName:@"UncaughtTestException"
                                   reason:@"This is an intentionally uncaught exception for crash testing"
                                 userInfo:@{
                                     @"test_type": @"uncaught_exception",
                                     @"timestamp": [NSDate date]
                                 }];
}

+ (void)triggerSegfaultCrash {
    // Trigger SIGSEGV by accessing unmapped memory
    volatile int *badAddress = (int *)0xDEADBEEF;
    *badAddress = 42;
}

+ (void)triggerBusErrorCrash {
    // Trigger SIGBUS via misaligned memory access
    // On ARM, misaligned access to certain types causes SIGBUS
#if defined(__arm64__)
    char *ptr = malloc(10);
    volatile int *misaligned = (int *)(ptr + 1); // Misaligned address
    *misaligned = 42;
    free(ptr);
#else
    // On x86, misaligned access is usually allowed, so raise signal directly
    raise(SIGBUS);
#endif
}

+ (void)triggerDivideByZeroCrash {
    // Trigger SIGFPE via integer divide by zero
    // Note: On ARM, integer divide by zero doesn't trap by default
    // We use volatile to prevent compiler optimization
    volatile int zero = 0;
    volatile int result = 1 / zero;
    (void)result; // Suppress unused variable warning
}

+ (void)triggerTrapCrash {
    // Trigger SIGTRAP (debugger trap / breakpoint)
#if defined(__arm64__)
    __asm__ volatile("brk #0"); // Breakpoint on ARM64
#elif defined(__x86_64__)
    __asm__ volatile("int3"); // Breakpoint on x86_64
#else
    raise(SIGTRAP);
#endif
}

@end
