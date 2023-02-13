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
 * A queue of objects. This object should not be allocated directly.
 * It serves as a base implementation for its child classes.
 */
@interface CASObjectQueue<T: id<NSCoding>> : NSObject

/**
 * Adds an element to the end of the queue.
 */
- (void)add:(T)data;

/**
 * Returns the number of elements in this queue.
 */
- (NSUInteger)size;

/**
 * Returns true if this queue contains no entries.
 */
- (BOOL)isEmpty;

/**
 * Returns the head of the queue, or nil if the queue is empty. Does not modify the
 * queue.
 */
- (nullable T)peek;

/**
 * Reads up to the specified amount of entries from the head of the queue without removing
 * the entries.
 * If the queue's @c size() is less than the amount specified, then only @c size() entries
 * are read.
 */
- (NSArray<T> *)peek:(NSUInteger)amount;

/**
 * Removes the head of the queue.
 */
- (void)pop;

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
