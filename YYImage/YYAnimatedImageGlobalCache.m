//
//  YYAnimatedImageGlobalCache.m
//  YYImage
//

#import "YYAnimatedImageGlobalCache.h"
#import <UIKit/UIKit.h>
#import <mach/mach.h>

static int64_t _YYDeviceMemoryTotalBytes() {
    int64_t mem = [[NSProcessInfo processInfo] physicalMemory];
    if (mem < -1) mem = -1;
    return mem;
}

@interface YYAnimatedImageGlobalCache () {
    dispatch_queue_t _queue; // serial for state
    uint64_t _usedBytes;
    NSTimer *_expandTimer;
    NSDate *_lastMemWarning;
}
@end

@implementation YYAnimatedImageGlobalCache

+ (instancetype)shared {
    static YYAnimatedImageGlobalCache *instance;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[YYAnimatedImageGlobalCache alloc] initPrivate];
    });
    return instance;
}

- (instancetype)initPrivate {
    self = [super init];
    if (!self) return nil;
    _queue = dispatch_queue_create("com.yyimage.animated.globalcache", DISPATCH_QUEUE_SERIAL);
    _usedBytes = 0;
    _shrinkFactor = 0.7;
    _shrinkCooldown = 10.0;
    _expandFactor = 1.15;
    _expandCheckInterval = 5.0;
    _expandAfter = 30.0;
    _minimumCacheBytes = 10ull * 1024ull * 1024ull; // 10MB
    uint64_t total = (uint64_t)_YYDeviceMemoryTotalBytes();
    _maximumCacheBytes = (uint64_t)(total * 0.2); // 20% of physical
    _maxCacheBytes = MAX(_minimumCacheBytes, MIN(_maximumCacheBytes, (uint64_t)(total * 0.1))); // start with 10%

    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(onMemoryWarning:) name:UIApplicationDidReceiveMemoryWarningNotification object:nil];

    [self startExpandTimer];
    return self;
}

- (instancetype)init {
    NSAssert(NO, @"Use +shared");
    return [self initPrivate];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [self stopExpandTimer];
}

- (uint64_t)usedCacheBytes {
    __block uint64_t v = 0;
    dispatch_sync(_queue, ^{ v = self->_usedBytes; });
    return v;
}

- (NSDate *)lastMemoryWarningDate {
    __block NSDate *v = nil;
    dispatch_sync(_queue, ^{ v = self->_lastMemWarning; });
    return v;
}

- (void)addBytes:(uint64_t)bytes {
    if (bytes == 0) return;
    dispatch_async(_queue, ^{ self->_usedBytes += bytes; });
}

- (void)removeBytes:(uint64_t)bytes {
    if (bytes == 0) return;
    dispatch_async(_queue, ^{
        if (bytes >= self->_usedBytes) self->_usedBytes = 0; else self->_usedBytes -= bytes;
    });
}

- (BOOL)isOverBudget {
    __block BOOL over = NO;
    dispatch_sync(_queue, ^{
        over = (self->_usedBytes > self->_maxCacheBytes);
    });
    return over;
}

- (void)onMemoryWarning:(NSNotification *)note {
    [self handleMemoryWarning];
}

- (void)handleMemoryWarning {
    NSDate *now = [NSDate date];
    __block BOOL canShrink = NO;
    __block NSTimeInterval cooldown = 0;
    dispatch_sync(_queue, ^{
        cooldown = self->_shrinkCooldown;
        if (!self->_lastMemWarning || [[now dateByAddingTimeInterval:-cooldown] compare:self->_lastMemWarning] == NSOrderedDescending) {
            canShrink = YES;
            self->_lastMemWarning = now;
        }
    });
    if (!canShrink) return;

    double factor = self.shrinkFactor;
    if (factor <= 0.05) factor = 0.05;
    if (factor >= 0.99) factor = 0.99;

    dispatch_async(_queue, ^{
        uint64_t newMax = (uint64_t)((double)self->_maxCacheBytes * factor);
        if (newMax < self->_minimumCacheBytes) newMax = self->_minimumCacheBytes;
        self->_maxCacheBytes = newMax;
    });
}

- (void)startExpandTimer {
    [self stopExpandTimer];
    if (_expandCheckInterval <= 0) return;
    _expandTimer = [NSTimer scheduledTimerWithTimeInterval:_expandCheckInterval target:self selector:@selector(onExpandTimer:) userInfo:nil repeats:YES];
}

- (void)stopExpandTimer {
    if (_expandTimer) {
        [_expandTimer invalidate];
        _expandTimer = nil;
    }
}

- (void)setExpandCheckInterval:(NSTimeInterval)expandCheckInterval {
    _expandCheckInterval = expandCheckInterval;
    [self startExpandTimer];
}

- (void)onExpandTimer:(NSTimer *)t {
    [self tryExpandBudgetIfNeeded];
}

- (void)tryExpandBudgetIfNeeded {
    NSDate *now = [NSDate date];
    __block NSDate *last;
    __block uint64_t maxBytes;
    __block uint64_t used;
    __block uint64_t upper;
    __block NSTimeInterval after;
    dispatch_sync(_queue, ^{
        last = self->_lastMemWarning;
        maxBytes = self->_maxCacheBytes;
        used = self->_usedBytes;
        upper = self->_maximumCacheBytes;
        after = self->_expandAfter;
    });
    if (last && [now timeIntervalSinceDate:last] < after) return;
    if (used * 100 < maxBytes * 70) { // usage < 70% of budget
        double factor = self.expandFactor;
        if (factor < 1.01) factor = 1.01;
        if (factor > 2.0) factor = 2.0;
        dispatch_async(_queue, ^{
            uint64_t grown = (uint64_t)((double)maxBytes * factor);
            if (grown > upper) grown = upper;
            if (grown < self->_minimumCacheBytes) grown = self->_minimumCacheBytes;
            self->_maxCacheBytes = grown;
        });
    }
}

@end