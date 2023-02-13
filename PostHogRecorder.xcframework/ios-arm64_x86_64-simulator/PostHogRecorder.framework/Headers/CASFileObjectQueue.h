//  Copyright 2016 LinkedIn Corporation
//  Licensed under the BSD 2-Clause License (the "License");
//  you may not use this file except in compliance with the License.
//  You may obtain a copy of the License at https://opensource.org/licenses/BSD-2-Clause
//
//  Unless required by applicable law or agreed to in writing, software
//  distributed under the License is distributed on an "AS IS" BASIS,
//  WITHOUT WARRANTIES OF ANY KIND, either express or implied.
//  See the License for the specific language governing permissions and limitations under the License.

#import "CASObjectQueue.h"

NS_ASSUME_NONNULL_BEGIN

/**
 * A queue of objects that is backed by a file. Objects must conform to
 * protocol NSCoding to ensure proper serialization and deserialization.
 */
@interface CASFileObjectQueue<T: id<NSCoding>> : CASObjectQueue<T>

/**
 * Initializes an @c CASFileObjectQueue with a file in the application's Library directory,
 * returning nil if there was an error.
 * Note: Intermediate directories will not be created, create containing directory before initializing.
 */
- (nullable instancetype)initWithRelativePath:(NSString *)filePath error:(NSError * __autoreleasing * _Nullable)error;

/**
 * Initializes an @c CASFileObjectQueue with a file at the specified path,
 * returning nil if there was an error.
 * Note: Intermediate directories will not be created, create containing directory before initializing.
 */
- (nullable instancetype)initWithAbsolutePath:(NSString *)filePath error:(NSError * __autoreleasing * _Nullable)error;

- (instancetype)init NS_UNAVAILABLE;

@end

NS_ASSUME_NONNULL_END
