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
    
    // 计算总可用缓存
    NSUInteger totalAvailableCache = [self calculateTotalAvailableCache];
    
    // 收集播放器信息并计算权重
    NSMutableArray *playerInfos = [NSMutableArray array];
    CGFloat totalWeight = 0;
    
    @synchronized (self.players) {
        for (id<AnimationPlayerProtocol> player in self.players) {
            // 计算每个播放器的权重
            CGFloat weight = [self calculateWeightForPlayer:player];
            totalWeight += weight;
            
            [playerInfos addObject:@{
                @"player": player,
                @"weight": @(weight),
                @"minBuffer": @([self calculateMinBufferForPlayer:player]),
                @"idealBuffer": @([self calculateIdealBufferForPlayer:player])
            }];
        }
    }
    
    // 第一轮：确保每个播放器至少获得最小缓存
    NSUInteger remainingCache = totalAvailableCache;
    for (NSDictionary *info in playerInfos) {
        NSUInteger minBuffer = [info[@"minBuffer"] unsignedIntegerValue];
        remainingCache = (remainingCache > minBuffer) ? (remainingCache - minBuffer) : 0;
    }
    
    // 第二轮：根据权重分配剩余缓存
    for (NSDictionary *info in playerInfos) {
        id<AnimationPlayerProtocol> player = info[@"player"];
        CGFloat weight = [info[@"weight"] floatValue];
        NSUInteger minBuffer = [info[@"minBuffer"] unsignedIntegerValue];
        NSUInteger idealBuffer = [info[@"idealBuffer"] unsignedIntegerValue];
        
        // 基础分配 = 最小缓存 + 按权重分配的额外缓存
        NSUInteger extraCache = 0;
        if (totalWeight > 0 && remainingCache > 0) {
            extraCache = (NSUInteger)(remainingCache * weight / totalWeight);
        }
        
        NSUInteger allocatedCache = minBuffer + extraCache;
        
        // 不超过理想缓存大小
        allocatedCache = MIN(allocatedCache, idealBuffer);
        
        // 更新播放器缓存
        [player updateMaxBufferSize:allocatedCache];
        
        NSLog(@"Player %p: allocated %.2fMB (priority=%lu, weight=%.2f)",
              player,
              allocatedCache / 1024.0 / 1024.0,
              (unsigned long)player.priority,
              weight);
    }
    
    // 更新解码队列并发数
    [self updateDecodeConcurrency];
}

- (NSUInteger)calculateTotalAvailableCache {
    NSUInteger baseCache = 0;
    
    switch (self.memoryPressure) {
        case MemoryPressureLevelNormal:
            // 内存充足，可以使用较多缓存
            baseCache = 200 * 1024 * 1024; // 200MB total
            break;
            
        case MemoryPressureLevelWarning:
            // 内存警告
            if (self.cpuLoad == CPULoadLevelHigh) {
                // CPU负载高，增加缓存减少解码
                baseCache = 100 * 1024 * 1024; // 100MB total
            } else {
                // CPU负载低，可以减少缓存
                baseCache = 60 * 1024 * 1024; // 60MB total
            }
            break;
            
        case MemoryPressureLevelCritical:
            // 内存严重不足
            baseCache = 30 * 1024 * 1024; // 30MB total
            break;
    }
    
    return baseCache;
}

- (CGFloat)calculateWeightForPlayer:(id<AnimationPlayerProtocol>)player {
    // 基础权重由优先级决定
    CGFloat weight = (player.priority + 1) / 11.0; // 归一化到 0.09 - 1.0
    
    // 根据帧率调整权重（高帧率需要更多缓存）
    CGFloat frameRateFactor = 1.0;
    if (player.frameRate > 30) {
        frameRateFactor = 1.2;
    } else if (player.frameRate > 60) {
        frameRateFactor = 1.5;
    }
    
    // 根据帧大小调整权重（大帧需要更多缓存）
    CGFloat frameSizeFactor = 1.0;
    NSUInteger frameSize = player.frameSize;
    if (frameSize > 500 * 1024) { // > 500KB
        frameSizeFactor = 1.3;
    } else if (frameSize > 1024 * 1024) { // > 1MB
        frameSizeFactor = 1.5;
    }
    
    // 根据当前缓存使用率调整权重
    CGFloat usageRatio = 1.0;
    if (player.maxBufferSize > 0) {
        usageRatio = (CGFloat)player.currentBufferSize / player.maxBufferSize;
        // 如果缓存使用率高，说明需要更多缓存
        if (usageRatio > 0.8) {
            weight *= 1.2;
        }
    }
    
    return weight * frameRateFactor * frameSizeFactor;
}

- (NSUInteger)calculateMinBufferForPlayer:(id<AnimationPlayerProtocol>)player {
    // 最小缓存应该能存储一定数量的帧
    NSUInteger minFrames = 10; // 至少缓存10帧
    
    // 内存严重不足时减少最小帧数
    if (self.memoryPressure == MemoryPressureLevelCritical) {
        minFrames = 5;
    }
    
    NSUInteger minBuffer = player.frameSize * minFrames;
    
    // 确保最小1MB
    return MAX(minBuffer, 1024 * 1024);
}

- (NSUInteger)calculateIdealBufferForPlayer:(id<AnimationPlayerProtocol>)player {
    // 理想缓存能存储一定时长的动画
    NSUInteger idealSeconds = 2; // 理想情况缓存2秒
    
    if (self.memoryPressure == MemoryPressureLevelWarning) {
        idealSeconds = 1;
    } else if (self.memoryPressure == MemoryPressureLevelCritical) {
        idealSeconds = 0.5;
    }
    
    NSUInteger idealBuffer = player.frameSize * player.frameRate * idealSeconds;
    
    // 上限50MB per player
    return MIN(idealBuffer, 50 * 1024 * 1024);
}

- (void)updateDecodeConcurrency {
    NSInteger maxConcurrent = 2;
    
    switch (self.cpuLoad) {
        case CPULoadLevelLow:
            // CPU负载低，可以增加并发
            maxConcurrent = (self.memoryPressure == MemoryPressureLevelCritical) ? 8 : 6;
            break;
            
        case CPULoadLevelMedium:
            maxConcurrent = 4;
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