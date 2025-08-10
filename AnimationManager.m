#import "AnimationManager.h"
#import <mach/mach.h>
#import <mach/processor_info.h>
#import <mach/mach_host.h>

@interface AnimationManager ()

@property (nonatomic, strong) NSMutableArray<id<AnimationPlayerProtocol>> *players;
@property (nonatomic, strong) NSOperationQueue *decodeQueue;
@property (nonatomic, strong) NSTimer *monitorTimer;

@property (nonatomic, assign) MemoryPressureLevel memoryPressure;
@property (nonatomic, assign) CPULoadLevel cpuLoad;

@end

@implementation AnimationManager

+ (instancetype)sharedManager {
    static AnimationManager *manager = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        manager = [[AnimationManager alloc] init];
    });
    return manager;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _players = [NSMutableArray array];
        _decodeQueue = [[NSOperationQueue alloc] init];
        _decodeQueue.maxConcurrentOperationCount = 2; // 默认并发数
        
        [self startMonitoring];
    }
    return self;
}

- (void)dealloc {
    [self stopMonitoring];
}

#pragma mark - Properties

- (NSArray<id<AnimationPlayerProtocol>> *)allPlayers {
    @synchronized (self.players) {
        return [self.players copy];
    }
}

#pragma mark - Player Management

- (void)registerPlayer:(id<AnimationPlayerProtocol>)player {
    @synchronized (self.players) {
        if (![self.players containsObject:player]) {
            [self.players addObject:player];
        }
    }
    [self updateCacheStrategy];
}

- (void)unregisterPlayer:(id<AnimationPlayerProtocol>)player {
    @synchronized (self.players) {
        [self.players removeObject:player];
    }
}

#pragma mark - Decode Task Management

- (void)submitDecodeTask:(NSOperation *)task forPlayer:(id<AnimationPlayerProtocol>)player {
    [self.decodeQueue addOperation:task];
}

#pragma mark - Monitoring

- (void)startMonitoring {
    self.monitorTimer = [NSTimer scheduledTimerWithTimeInterval:2.0
                                                         target:self
                                                       selector:@selector(monitorSystemResources)
                                                       userInfo:nil
                                                        repeats:YES];
}

- (void)stopMonitoring {
    [self.monitorTimer invalidate];
    self.monitorTimer = nil;
}

- (void)monitorSystemResources {
    [self updateMemoryPressure];
    [self updateCPULoad];
    [self updateCacheStrategy];
}

#pragma mark - Memory Monitoring

- (void)updateMemoryPressure {
    vm_size_t pageSize = vm_page_size;
    mach_port_t hostPort = mach_host_self();
    vm_statistics64_data_t vmStat;
    mach_msg_type_number_t hostSize = sizeof(vm_statistics64_data_t) / sizeof(natural_t);
    
    if (host_statistics64(hostPort, HOST_VM_INFO64, (host_info64_t)&vmStat, &hostSize) != KERN_SUCCESS) {
        return;
    }
    
    natural_t memFree = vmStat.free_count + vmStat.inactive_count;
    natural_t memUsed = vmStat.active_count + vmStat.wire_count;
    natural_t memTotal = memFree + memUsed;
    
    float memUsageRatio = (float)memUsed / (float)memTotal;
    
    if (memUsageRatio > 0.85) {
        self.memoryPressure = MemoryPressureLevelCritical;
    } else if (memUsageRatio > 0.7) {
        self.memoryPressure = MemoryPressureLevelWarning;
    } else {
        self.memoryPressure = MemoryPressureLevelNormal;
    }
}

#pragma mark - CPU Monitoring

- (void)updateCPULoad {
    processor_info_array_t cpuInfo;
    mach_msg_type_number_t numCpuInfo;
    natural_t numCpus = 0;
    
    kern_return_t kr = host_processor_info(mach_host_self(),
                                          PROCESSOR_CPU_LOAD_INFO,
                                          &numCpus,
                                          &cpuInfo,
                                          &numCpuInfo);
    
    if (kr != KERN_SUCCESS) {
        return;
    }
    
    float totalUsage = 0;
    for (natural_t i = 0; i < numCpus; i++) {
        float inUse = cpuInfo[(CPU_STATE_MAX * i) + CPU_STATE_USER] +
                      cpuInfo[(CPU_STATE_MAX * i) + CPU_STATE_SYSTEM] +
                      cpuInfo[(CPU_STATE_MAX * i) + CPU_STATE_NICE];
        float total = inUse + cpuInfo[(CPU_STATE_MAX * i) + CPU_STATE_IDLE];
        
        if (total > 0) {
            totalUsage += (inUse / total);
        }
    }
    
    float avgUsage = totalUsage / numCpus;
    
    if (avgUsage > 0.8) {
        self.cpuLoad = CPULoadLevelHigh;
    } else if (avgUsage > 0.5) {
        self.cpuLoad = CPULoadLevelMedium;
    } else {
        self.cpuLoad = CPULoadLevelLow;
    }
    
    vm_deallocate(mach_task_self(), (vm_address_t)cpuInfo, sizeof(processor_info_array_t) * numCpuInfo);
}

#pragma mark - Cache Strategy

- (void)updateCacheStrategy {
    NSUInteger playerCount = self.players.count;
    if (playerCount == 0) return;
    
    // 计算当前实际使用的总缓存
    NSUInteger totalUsedCache = 0;
    @synchronized (self.players) {
        for (id<AnimationPlayerProtocol> player in self.players) {
            totalUsedCache += player.currentBufferSize;
        }
    }
    
    // 根据内存压力计算可用缓存上限
    NSUInteger maxTotalCache = [self calculateMaxTotalCache];
    
    // 如果当前使用已接近上限，需要收缩
    BOOL needShrink = (totalUsedCache > maxTotalCache * 0.9);
    
    // 计算每个播放器的缓存配额
    @synchronized (self.players) {
        for (id<AnimationPlayerProtocol> player in self.players) {
            NSUInteger newBufferSize = [self calculateBufferSizeForPlayer:player 
                                                        withTotalCache:maxTotalCache 
                                                           playerCount:playerCount
                                                            needShrink:needShrink];
            [player updateMaxBufferSize:newBufferSize];
        }
    }
    
    // 更新解码队列并发数
    [self updateDecodeConcurrency];
    
    NSLog(@"Cache strategy updated: %lu players, total used: %.2fMB / %.2fMB",
          (unsigned long)playerCount,
          totalUsedCache / 1024.0 / 1024.0,
          maxTotalCache / 1024.0 / 1024.0);
}

- (NSUInteger)calculateMaxTotalCache {
    NSUInteger baseCache = 0;
    
    switch (self.memoryPressure) {
        case MemoryPressureLevelNormal:
            // 内存充足，但采用渐进式策略
            // 初始不分配太多，根据实际使用情况逐步增加
            baseCache = 100 * 1024 * 1024; // 100MB total (而不是200MB)
            break;
            
        case MemoryPressureLevelWarning:
            // 内存警告
            if (self.cpuLoad == CPULoadLevelHigh) {
                baseCache = 60 * 1024 * 1024; // 60MB total
            } else {
                baseCache = 40 * 1024 * 1024; // 40MB total
            }
            break;
            
        case MemoryPressureLevelCritical:
            // 内存严重不足
            baseCache = 20 * 1024 * 1024; // 20MB total
            break;
    }
    
    return baseCache;
}

- (NSUInteger)calculateBufferSizeForPlayer:(id<AnimationPlayerProtocol>)player
                            withTotalCache:(NSUInteger)totalCache
                               playerCount:(NSUInteger)playerCount
                                needShrink:(BOOL)needShrink {
    
    // 基础分配：平均分配
    NSUInteger baseAllocation = totalCache / playerCount;
    
    // 根据帧特征调整
    CGFloat adjustmentFactor = 1.0;
    
    // 帧大小调整因子
    if (player.frameSize > 500 * 1024) {
        adjustmentFactor *= 1.2; // 大帧需要更多缓存
    } else if (player.frameSize < 50 * 1024) {
        adjustmentFactor *= 0.8; // 小帧需要较少缓存
    }
    
    // 帧率调整因子
    if (player.frameRate > 30) {
        adjustmentFactor *= 1.1;
    } else if (player.frameRate < 15) {
        adjustmentFactor *= 0.9;
    }
    
    NSUInteger adjustedAllocation = (NSUInteger)(baseAllocation * adjustmentFactor);
    
    // 计算最小和最大边界
    NSUInteger minBuffer = [self calculateMinBufferForPlayer:player];
    NSUInteger maxBuffer = [self calculateMaxBufferForPlayer:player];
    
    // 应用边界限制
    adjustedAllocation = MAX(adjustedAllocation, minBuffer);
    adjustedAllocation = MIN(adjustedAllocation, maxBuffer);
    
    // 如果需要收缩，渐进式减少
    if (needShrink && player.currentBufferSize > adjustedAllocation) {
        // 逐步减少，每次减少20%
        NSUInteger targetSize = player.currentBufferSize * 0.8;
        adjustedAllocation = MAX(targetSize, adjustedAllocation);
    }
    
    // 渐进式增长策略
    if (!needShrink && player.maxBufferSize < adjustedAllocation) {
        // 检查当前缓存使用率
        CGFloat usageRate = 0;
        if (player.maxBufferSize > 0) {
            usageRate = (CGFloat)player.currentBufferSize / player.maxBufferSize;
        }
        
        // 只有当使用率超过70%时才增加缓存
        if (usageRate > 0.7) {
            // 每次增长50%，但不超过目标值
            NSUInteger newSize = player.maxBufferSize * 1.5;
            adjustedAllocation = MIN(newSize, adjustedAllocation);
        } else {
            // 使用率低，保持当前大小
            adjustedAllocation = player.maxBufferSize;
        }
    }
    
    return adjustedAllocation;
}

- (NSUInteger)calculateMinBufferForPlayer:(id<AnimationPlayerProtocol>)player {
    // 最小缓存：至少能存储5-10帧
    NSUInteger minFrames = 5;
    if (self.memoryPressure != MemoryPressureLevelCritical) {
        minFrames = 10;
    }
    
    NSUInteger minBuffer = player.frameSize * minFrames;
    // 确保最小1MB
    return MAX(minBuffer, 1024 * 1024);
}

- (NSUInteger)calculateMaxBufferForPlayer:(id<AnimationPlayerProtocol>)player {
    // 最大缓存：限制单个播放器不能占用过多内存
    // 根据内存压力设置不同上限
    NSUInteger maxBuffer = 30 * 1024 * 1024; // 30MB
    
    if (self.memoryPressure == MemoryPressureLevelWarning) {
        maxBuffer = 20 * 1024 * 1024; // 20MB
    } else if (self.memoryPressure == MemoryPressureLevelCritical) {
        maxBuffer = 10 * 1024 * 1024; // 10MB
    }
    
    // 或者最多存储2秒的动画
    NSUInteger twoSecondsBuffer = player.frameSize * player.frameRate * 2;
    return MIN(maxBuffer, twoSecondsBuffer);
}

- (void)updateDecodeConcurrency {
    NSInteger maxConcurrent = 2;
    
    switch (self.cpuLoad) {
        case CPULoadLevelLow:
            // CPU负载低，可以增加并发
            maxConcurrent = (self.memoryPressure == MemoryPressureLevelCritical) ? 6 : 4;
            break;
            
        case CPULoadLevelMedium:
            maxConcurrent = 3;
            break;
            
        case CPULoadLevelHigh:
            // CPU负载高，减少并发
            maxConcurrent = 2;
            break;
    }
    
    self.decodeQueue.maxConcurrentOperationCount = maxConcurrent;
    
    NSLog(@"Decode concurrency updated to %ld", (long)maxConcurrent);
}

@end