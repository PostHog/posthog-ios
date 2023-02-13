[![Build Status](https://dev.azure.com/lnkd-oss/cassette/_apis/build/status/linkedin.cassette?branchName=master)](https://dev.azure.com/lnkd-oss/cassette/_build/latest?definitionId=4&branchName=master)

# Cassette 

Cassette is a collection of queue-related classes for iOS and macOS. It is maintained by [LinkedIn](https://engineering.linkedin.com/). Cassette was originally implemented by [Segment](https://segment.com). Cassette was inspired by [Tape](https://github.com/square/tape).

`QueueFile` is an efficient, file-based FIFO queue. Addition and removal from an instance is an O(1) operation. Writes are synchronous; data will be written to disk before an operation returns. The queue is intended to be reliable and survive system or process crashes.

## Installing the Library

#### CocoaPods
```
target 'MyApp' do
  pod 'Cassette', '1.0.0-beta3'
end
```

#### Manual
Download the [latest binary](https://github.com/linkedin/cassette/releases) of the library.

## Usage
`CASObjectQueue` works with arbitrary objects that abide by the [NSCoding](https://developer.apple.com/documentation/foundation/nscoding?language=objc) protocol. An `CASObjectQueue` may be backed by a persistent `CASQueueFile`, or in memory. 

```
CASObjectQueue<NSNumber *> *queue;

// Persistent ObjectQueue
NSError *error;
queue = [[CASFileObjectQueue alloc] initWithRelativePath:@"Test-File" error:&error];

// In-Memory ObjectQueue
queue = [[CASInMemoryObjectQueue alloc] init];
```

Add some data to the end of the queue.
```
[queue add:@1];
```

Read data at the head of the queue.
```
// Peek the eldest element.
NSNumber *data = [queue peek];

// Peek the eldest `n` elements.
NSArray<NSNumber *> *data = [queue peek:n];
```

Remove processed elements.
```
// Remove the eldest element.
[queue pop];

// Remove 'n' elements.
[queue pop:n];

// Remove all elements.
[queue clear];
```
