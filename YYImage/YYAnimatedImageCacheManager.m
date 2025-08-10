//
//  YYAnimatedImageCacheManager.m
//  YYImage <https://github.com/ibireme/YYImage>
//
//  Created by ibireme on 14/10/19.
//  Copyright (c) 2015 ibireme.
//
//  This source code is licensed under the MIT-style license found in the
//  LICENSE file in the root directory of this source tree.
//

#import "YYAnimatedImageCacheManager.h"
#import <mach/mach.h>
#import <pthread.h>

// 动图缓存信息
@interface YYAnimatedImageCacheInfo : NSObject
@property (nonatomic, copy) NSString *imageId;
@property (nonatomic, assign) NSUInteger frameSize;
@property (nonatomic, assign) NSUInteger frameCount;
@property (nonatomic, assign) NSUInteger cachedFrameCount;
@property (nonatomic, assign) NSUInteger usedCacheSize;
@end

@implementation YYAnimatedImageCacheInfo
@end

@interface YYAnimatedImageCacheManager ()
@property (nonatomic, strong) NSMutableDictionary<NSString *, YYAnimatedImageCacheInfo *> *imageCacheInfos;
@property (nonatomic, strong) dispatch_semaphore_t lock;
@property (nonatomic, strong) NSTimer *memoryCheckTimer;
@property (nonatomic, assign) NSTimeInterval lastMemoryWarningTime;
@property (nonatomic, assign) NSUInteger currentMaxCacheSize;
@property (nonatomic, assign) NSUInteger currentUsedCacheSize;
@end

@implementation YYAnimatedImageCacheManager

+ (instancetype)sharedManager {
    static YYAnimatedImageCacheManager *manager = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        manager = [[YYAnimatedImageCacheManager alloc] init];
    });
    return manager;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _imageCacheInfos = [NSMutableDictionary dictionary];
        _lock = dispatch_semaphore_create(1);
        
        // 设置默认值
        _memoryWarningReductionRatio = 0.5;
        _memorySufficientGrowthRatio = 1.2;
        _memoryWarningMinInterval = 30.0;
        _memorySufficientCheckInterval = 60.0;
        
        // 计算初始最大缓存大小（设备内存的20%）
        int64_t totalMemory = [self deviceTotalMemory];
        _maxCacheSize = (NSUInteger)(totalMemory * 0.2);
        _currentMaxCacheSize = _maxCacheSize;
        
        // 注册内存警告通知
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(handleMemoryWarningNotification:)
                                                     name:UIApplicationDidReceiveMemoryWarningNotification
                                                   object:nil];
        
        // 启动内存检查定时器
        [self startMemoryCheckTimer];
    }
    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [self stopMemoryCheckTimer];
}

#pragma mark - Public Methods

- (NSUInteger)availableCacheSize {
    dispatch_semaphore_wait(_lock, DISPATCH_TIME_FOREVER);
    NSUInteger available = _currentMaxCacheSize - _currentUsedCacheSize;
    dispatch_semaphore_signal(_lock);
    return available;
}

- (NSUInteger)usedCacheSize {
    dispatch_semaphore_wait(_lock, DISPATCH_TIME_FOREVER);
    NSUInteger used = _currentUsedCacheSize;
    dispatch_semaphore_signal(_lock);
    return used;
}

- (void)setMaxCacheSize:(NSUInteger)maxCacheSize {
    dispatch_semaphore_wait(_lock, DISPATCH_TIME_FOREVER);
    _maxCacheSize = maxCacheSize;
    _currentMaxCacheSize = maxCacheSize;
    dispatch_semaphore_signal(_lock);
}

- (void)registerAnimatedImage:(NSString *)imageId 
                   frameSize:(NSUInteger)frameSize 
                  frameCount:(NSUInteger)frameCount {
    if (!imageId || frameSize == 0 || frameCount == 0) return;
    
    dispatch_semaphore_wait(_lock, DISPATCH_TIME_FOREVER);
    
    YYAnimatedImageCacheInfo *info = [[YYAnimatedImageCacheInfo alloc] init];
    info.imageId = imageId;
    info.frameSize = frameSize;
    info.frameCount = frameCount;
    info.cachedFrameCount = 0;
    info.usedCacheSize = 0;
    
    _imageCacheInfos[imageId] = info;
    
    dispatch_semaphore_signal(_lock);
}

- (void)unregisterAnimatedImage:(NSString *)imageId {
    if (!imageId) return;
    
    dispatch_semaphore_wait(_lock, DISPATCH_TIME_FOREVER);
    
    YYAnimatedImageCacheInfo *info = _imageCacheInfos[imageId];
    if (info) {
        _currentUsedCacheSize -= info.usedCacheSize;
        [_imageCacheInfos removeObjectForKey:imageId];
    }
    
    dispatch_semaphore_signal(_lock);
}

- (void)updateAnimatedImageCache:(NSString *)imageId 
                cachedFrameCount:(NSUInteger)cachedFrameCount {
    if (!imageId) return;
    
    dispatch_semaphore_wait(_lock, DISPATCH_TIME_FOREVER);
    
    YYAnimatedImageCacheInfo *info = _imageCacheInfos[imageId];
    if (info) {
        NSUInteger oldUsedSize = info.usedCacheSize;
        info.cachedFrameCount = cachedFrameCount;
        info.usedCacheSize = cachedFrameCount * info.frameSize;
        
        _currentUsedCacheSize = _currentUsedCacheSize - oldUsedSize + info.usedCacheSize;
    }
    
    dispatch_semaphore_signal(_lock);
}

- (BOOL)canCacheMoreFrames:(NSString *)imageId 
           additionalFrames:(NSUInteger)additionalFrames {
    if (!imageId || additionalFrames == 0) return NO;
    
    dispatch_semaphore_wait(_lock, DISPATCH_TIME_FOREVER);
    
    YYAnimatedImageCacheInfo *info = _imageCacheInfos[imageId];
    if (!info) {
        dispatch_semaphore_signal(_lock);
        return NO;
    }
    
    NSUInteger additionalSize = additionalFrames * info.frameSize;
    BOOL canCache = (_currentUsedCacheSize + additionalSize) <= _currentMaxCacheSize;
    
    dispatch_semaphore_signal(_lock);
    return canCache;
}

- (NSUInteger)suggestedCacheFrameCount:(NSString *)imageId {
    if (!imageId) return 0;
    
    dispatch_semaphore_wait(_lock, DISPATCH_TIME_FOREVER);
    
    YYAnimatedImageCacheInfo *info = _imageCacheInfos[imageId];
    if (!info) {
        dispatch_semaphore_signal(_lock);
        return 0;
    }
    
    NSUInteger availableSize = _currentMaxCacheSize - _currentUsedCacheSize;
    NSUInteger suggestedFrames = availableSize / info.frameSize;
    
    // 限制建议帧数不超过总帧数
    suggestedFrames = MIN(suggestedFrames, info.frameCount);
    
    dispatch_semaphore_signal(_lock);
    return suggestedFrames;
}

- (void)clearAllCache {
    dispatch_semaphore_wait(_lock, DISPATCH_TIME_FOREVER);
    
    for (YYAnimatedImageCacheInfo *info in _imageCacheInfos.allValues) {
        info.cachedFrameCount = 0;
        info.usedCacheSize = 0;
    }
    _currentUsedCacheSize = 0;
    
    dispatch_semaphore_signal(_lock);
}

- (void)handleMemoryWarning {
    [self handleMemoryWarningNotification:nil];
}

#pragma mark - Private Methods

- (void)handleMemoryWarningNotification:(NSNotification *)notification {
    NSTimeInterval currentTime = [[NSDate date] timeIntervalSince1970];
    
    // 检查是否超过最小间隔时间
    if (currentTime - _lastMemoryWarningTime < _memoryWarningMinInterval) {
        return;
    }
    
    _lastMemoryWarningTime = currentTime;
    
    dispatch_semaphore_wait(_lock, DISPATCH_TIME_FOREVER);
    
    // 减少缓存大小
    NSUInteger newMaxCacheSize = (NSUInteger)(_currentMaxCacheSize * _memoryWarningReductionRatio);
    newMaxCacheSize = MAX(newMaxCacheSize, 1024 * 1024); // 最小1MB
    
    _currentMaxCacheSize = newMaxCacheSize;
    
    // 如果当前使用量超过新的最大值，清理缓存
    if (_currentUsedCacheSize > _currentMaxCacheSize) {
        [self cleanupExcessCache];
    }
    
    dispatch_semaphore_signal(_lock);
    
    NSLog(@"YYAnimatedImageCacheManager: Memory warning handled, cache size reduced to %lu bytes", (unsigned long)_currentMaxCacheSize);
}

- (void)checkMemorySufficient {
    NSTimeInterval currentTime = [[NSDate date] timeIntervalSince1970];
    
    // 检查距离上次内存警告是否超过检查间隔
    if (currentTime - _lastMemoryWarningTime < _memorySufficientCheckInterval) {
        return;
    }
    
    dispatch_semaphore_wait(_lock, DISPATCH_TIME_FOREVER);
    
    // 检查当前内存使用情况
    int64_t freeMemory = [self deviceFreeMemory];
    int64_t totalMemory = [self deviceTotalMemory];
    
    // 如果可用内存超过总内存的30%，可以增加缓存大小
    if (freeMemory > totalMemory * 0.3) {
        NSUInteger newMaxCacheSize = (NSUInteger)(_currentMaxCacheSize * _memorySufficientGrowthRatio);
        newMaxCacheSize = MIN(newMaxCacheSize, _maxCacheSize); // 不超过原始最大值
        
        if (newMaxCacheSize > _currentMaxCacheSize) {
            _currentMaxCacheSize = newMaxCacheSize;
            NSLog(@"YYAnimatedImageCacheManager: Memory sufficient, cache size increased to %lu bytes", (unsigned long)_currentMaxCacheSize);
        }
    }
    
    dispatch_semaphore_signal(_lock);
}

- (void)cleanupExcessCache {
    // 按使用时间排序，优先清理使用较少的缓存
    NSArray *sortedInfos = [_imageCacheInfos.allValues sortedArrayUsingComparator:^NSComparisonResult(YYAnimatedImageCacheInfo *obj1, YYAnimatedImageCacheInfo *obj2) {
        // 这里可以根据实际需求调整排序策略
        // 暂时按缓存大小排序，优先清理大的缓存
        if (obj1.usedCacheSize > obj2.usedCacheSize) {
            return NSOrderedAscending;
        } else if (obj1.usedCacheSize < obj2.usedCacheSize) {
            return NSOrderedDescending;
        }
        return NSOrderedSame;
    }];
    
    NSUInteger excessSize = _currentUsedCacheSize - _currentMaxCacheSize;
    NSUInteger cleanedSize = 0;
    
    for (YYAnimatedImageCacheInfo *info in sortedInfos) {
        if (cleanedSize >= excessSize) break;
        
        NSUInteger cleanSize = MIN(info.usedCacheSize, excessSize - cleanedSize);
        NSUInteger cleanFrames = cleanSize / info.frameSize;
        
        if (cleanFrames > 0) {
            info.cachedFrameCount = MAX(0, info.cachedFrameCount - cleanFrames);
            info.usedCacheSize = info.cachedFrameCount * info.frameSize;
            cleanedSize += cleanSize;
        }
    }
    
    _currentUsedCacheSize -= cleanedSize;
}

- (void)startMemoryCheckTimer {
    [self stopMemoryCheckTimer];
    
    _memoryCheckTimer = [NSTimer scheduledTimerWithTimeInterval:_memorySufficientCheckInterval
                                                         target:self
                                                       selector:@selector(checkMemorySufficient)
                                                       userInfo:nil
                                                        repeats:YES];
    [[NSRunLoop mainRunLoop] addTimer:_memoryCheckTimer forMode:NSRunLoopCommonModes];
}

- (void)stopMemoryCheckTimer {
    [_memoryCheckTimer invalidate];
    _memoryCheckTimer = nil;
}

- (int64_t)deviceTotalMemory {
    int64_t mem = [[NSProcessInfo processInfo] physicalMemory];
    if (mem < -1) mem = -1;
    return mem;
}

- (int64_t)deviceFreeMemory {
    mach_port_t host_port = mach_host_self();
    mach_msg_type_number_t host_size = sizeof(vm_statistics_data_t) / sizeof(integer_t);
    vm_size_t page_size;
    vm_statistics_data_t vm_stat;
    kern_return_t kern;
    
    kern = host_page_size(host_port, &page_size);
    if (kern != KERN_SUCCESS) return -1;
    kern = host_statistics(host_port, HOST_VM_INFO, (host_info_t)&vm_stat, &host_size);
    if (kern != KERN_SUCCESS) return -1;
    return vm_stat.free_count * page_size;
}

@end