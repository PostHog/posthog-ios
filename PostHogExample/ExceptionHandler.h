//
//  ExceptionHandler.h
//  PostHogExample
//
//  Created for NSException handling in Swift
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface ExceptionHandler : NSObject

/// Execute a block and catch any NSExceptions that occur
/// @param tryBlock The block to execute that might throw an NSException
/// @param catchBlock The block to execute if an NSException is caught
+ (void)tryBlock:(void(^)(void))tryBlock 
           catch:(void(^)(NSException *exception))catchBlock;

/// Execute a block and catch any NSExceptions, with optional finally block
/// @param tryBlock The block to execute that might throw an NSException
/// @param catchBlock The block to execute if an NSException is caught
/// @param finallyBlock The block to execute regardless of whether an exception occurred
+ (void)tryBlock:(void(^)(void))tryBlock 
           catch:(void(^)(NSException *exception))catchBlock
         finally:(nullable void(^)(void))finallyBlock;

/// Trigger a sample NSRangeException for testing purposes  
+ (void)triggerSampleRangeException;

/// Trigger a sample NSInvalidArgumentException for testing purposes
+ (void)triggerSampleInvalidArgumentException;

/// Trigger a sample NSGenericException for testing purposes
+ (void)triggerSampleGenericException;

/// Trigger a chained exception scenario for testing exception chaining
/// This demonstrates how exceptions can be caught and rethrown with additional context
+ (void)triggerChainedException;

// MARK: - Crash Triggers for Testing

/// Trigger an uncaught NSException
+ (void)triggerUncaughtNSException;

/// Trigger a null pointer dereference (EXC_BAD_ACCESS)
+ (void)triggerNullPointerCrash;

/// Trigger an abort signal (SIGABRT)
+ (void)triggerAbortCrash;

@end

NS_ASSUME_NONNULL_END
