#import "AnimationManager.h"
#import <mach/mach.h>
#import <mach/processor_info.h>
#import <mach/mach_host.h>

@interface AnimationManager ()

@property (nonatomic, strong) NSMutableSet<id<AnimationPlayerProtocol>> *players;
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
        _players = [NSMutableSet set];
        _decodeQueue = [[NSOperationQueue alloc] init];
        _decodeQueue.maxConcurrentOperationCount = 2; // 默认并发数
        
        [self startMonitoring];
    }
    return self;
}

- (void)dealloc {
    [self stopMonitoring];
}

#pragma mark - Player Management

- (void)registerPlayer:(id<AnimationPlayerProtocol>)player {
    @synchronized (self.players) {
        [self.players addObject:player];
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
    
    // 根据内存压力和CPU负载调整策略
    NSUInteger bufferSizePerPlayer = 0;
    NSInteger maxConcurrent = 2;
    
    switch (self.memoryPressure) {
        case MemoryPressureLevelNormal:
            // 内存充足，全部缓存
            bufferSizePerPlayer = 50 * 1024 * 1024; // 50MB per player
            maxConcurrent = 4;
            break;
            
        case MemoryPressureLevelWarning:
            // 内存警告，根据CPU负载调整
            if (self.cpuLoad == CPULoadLevelHigh) {
                // CPU负载高，多缓存减少解码
                bufferSizePerPlayer = 20 * 1024 * 1024; // 20MB per player
                maxConcurrent = 2;
            } else {
                // CPU负载低，可以减少缓存增加并发
                bufferSizePerPlayer = 10 * 1024 * 1024; // 10MB per player
                maxConcurrent = 6;
            }
            break;
            
        case MemoryPressureLevelCritical:
            // 内存严重不足，最小缓存
            bufferSizePerPlayer = 5 * 1024 * 1024; // 5MB per player
            if (self.cpuLoad == CPULoadLevelLow) {
                maxConcurrent = 8;
            } else {
                maxConcurrent = 2;
            }
            break;
    }
    
    // 根据播放器数量调整每个播放器的缓存
    if (playerCount > 1) {
        bufferSizePerPlayer = bufferSizePerPlayer / playerCount;
        // 确保每个播放器至少有2MB缓存
        bufferSizePerPlayer = MAX(bufferSizePerPlayer, 2 * 1024 * 1024);
    }
    
    // 更新解码队列并发数
    self.decodeQueue.maxConcurrentOperationCount = maxConcurrent;
    
    // 通知所有播放器更新缓存大小
    @synchronized (self.players) {
        for (id<AnimationPlayerProtocol> player in self.players) {
            [player updateMaxBufferSize:bufferSizePerPlayer];
        }
    }
    
    NSLog(@"Cache strategy updated: %lu players, %luMB per player, %ld concurrent operations",
          (unsigned long)playerCount,
          (unsigned long)(bufferSizePerPlayer / 1024 / 1024),
          (long)maxConcurrent);
}

@end