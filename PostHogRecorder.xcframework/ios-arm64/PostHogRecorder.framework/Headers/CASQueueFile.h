//  Copyright 2016 LinkedIn Corporation
//  Licensed under the BSD 2-Clause License (the "License");
//  you may not use this file except in compliance with the License.
//  You may obtain a copy of the License at https://opensource.org/licenses/BSD-2-Clause
//
//  Unless required by applicable law or agreed to in writing, software
//  distributed under the License is distributed on an "AS IS" BASIS,
//  WITHOUT WARRANTIES OF ANY KIND, either express or implied.
//  See the License for the specific language governing permissions and limitations under the License.

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/**
 * A reliable, efficient, file-based, FIFO queue. Additions and removals are O(1). All operations
 * are atomic. Writes are synchronous; data will be written to disk before an operation returns.
 * The underlying file is structured to survive process and even system crashes. If an I/O
 * exception is thrown during a mutating change, the change is aborted. It is safe to continue to
 * use a @c CASQueueFile instance after an exception.
 *
 * <p><strong>Note that this implementation is not synchronized.</strong>
 */
@interface CASQueueFile : NSObject

/**
 * The primary way to construct an @c LITapeQueueFile.
 */
+ (nullable CASQueueFile *)queueFileWithPath:(NSString *)path error:(NSError * __autoreleasing * _Nullable)error;

/**
 * Initializing the queue file directly is unavailable.
 * Please use the API @c queueFileWithPath
 */
- (instancetype)init NS_UNAVAILABLE;

/**
 * Adds an element to the end of the queue.
 */
- (void)add:(NSData *)data;

/**
 * Returns the number of elements in this queue.
 */
- (NSUInteger)size;

/**
 * Returns true if this queue contains no entries.
 */
- (BOOL)isEmpty;

/**
 * Reads up to the specified amount of entries from the head of the queue without removing
 * the entries.
 * If the queue's @c size() is less than the amount specified, then only @c size() entries
 * are read.
 */
- (NSArray<NSData *> *)peek:(NSUInteger)amount;

/**
 * Removes the specified amount of entries from the head of the queue.
 */
- (void)pop:(NSUInteger)amount;

/**
 * Clears this queue. Truncates the file to the initial size.
 */
- (void)clear;

@end

NS_ASSUME_NONNULL_END
