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
 * Object-based wrapper for dealing with elements in a @c CASQueueFile.
 */
@interface CASQueueFileElement : NSObject

/**
 * The position this element starts at in the @c CASQueueFile.
 */
@property (nonatomic, assign) NSUInteger position;

/**
 * The amount of bytes this element occupies.
 */
@property (nonatomic, assign) NSUInteger length;

/**
 * Helper initializer to allocate an element such that it represents a nil element.
 * Both position and length are initialized to zero.
 */
+ (instancetype)null;
- (instancetype)initAtPosition:(NSUInteger)position withLength:(NSUInteger)length NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

@end

NS_ASSUME_NONNULL_END
