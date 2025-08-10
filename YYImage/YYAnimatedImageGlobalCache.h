//
//  YYAnimatedImageGlobalCache.h
//  YYImage
//
//  Global animated image memory cache manager.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface YYAnimatedImageGlobalCache : NSObject

+ (instancetype)shared;

// Maximum bytes allowed for all animated frame caches combined.
@property (atomic, assign) uint64_t maxCacheBytes;
// Current bytes used by all animated frame caches combined.
@property (atomic, readonly) uint64_t usedCacheBytes;

// Shrink behavior when receiving memory warning.
// maxCacheBytes will be multiplied by this factor (0 < factor < 1).
@property (atomic, assign) double shrinkFactor;            // default: 0.7
// Minimum interval between consecutive shrink operations triggered by memory warnings.
@property (atomic, assign) NSTimeInterval shrinkCooldown;  // default: 10s

// Expansion behavior when system looks stable.
// Periodically checks and if no memory warning for a while, expands the budget by this factor (> 1).
@property (atomic, assign) double expandFactor;            // default: 1.15
// Timer firing interval for checking expansion condition.
@property (atomic, assign) NSTimeInterval expandCheckInterval; // default: 5s
// If time since last memory warning exceeds this threshold, expansion can happen.
@property (atomic, assign) NSTimeInterval expandAfter;     // default: 30s

// Lower/upper bounds to avoid extreme values.
@property (atomic, assign) uint64_t minimumCacheBytes;     // default: 10MB
@property (atomic, assign) uint64_t maximumCacheBytes;     // default: 20% of physical memory (computed at init)

// The last time a memory warning was processed.
@property (atomic, strong, readonly, nullable) NSDate *lastMemoryWarningDate;

// Update used bytes when a frame is cached/evicted.
- (void)addBytes:(uint64_t)bytes;     // call when adding a decoded frame into any buffer
- (void)removeBytes:(uint64_t)bytes;  // call when removing a decoded frame from any buffer

// Whether the global usage currently exceeds the allowed budget.
- (BOOL)isOverBudget;

@end

NS_ASSUME_NONNULL_END