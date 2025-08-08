//
//  YYGlobalAnimatedImageManager.m
//  YYImage <https://github.com/ibireme/YYImage>
//
//  Created by Global Manager on 2024/12/19.
//

#import "YYGlobalAnimatedImageManager.h"
#import "YYAnimatedImageView.h"
#import <mach/mach.h>
#import <sys/sysctl.h>

#define MINIMUM_BUFFER_SIZE (2 * 1024 * 1024) // 2MB 最小缓存
#define DEFAULT_CONCURRENT_COUNT 2 // 默认并发数
#define MEMORY_CHECK_INTERVAL 2.0 // 内存检查间隔（秒）

@interface YYGlobalAnimatedImageManager ()

@property (nonatomic, strong) NSMutableSet<YYAnimatedImageView *> *registeredViews;
@property (nonatomic, strong) NSOperationQueue *globalDecodeQueue;
@property (nonatomic, strong) NSTimer *memoryMonitorTimer;
@property (nonatomic, assign) NSUInteger lastAvailableMemory;
@property (nonatomic, assign) double lastCPUUsage;
@property (nonatomic, strong) dispatch_semaphore_t managerLock;

@end

@implementation YYGlobalAnimatedImageManager

+ (instancetype)sharedManager {
    static YYGlobalAnimatedImageManager *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[YYGlobalAnimatedImageManager alloc] init];
    });
    return instance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _registeredViews = [NSMutableSet set];
        _globalDecodeQueue = [[NSOperationQueue alloc] init];
        _globalDecodeQueue.name = @"YYGlobalAnimatedImageDecodeQueue";
        _globalDecodeQueue.maxConcurrentOperationCount = DEFAULT_CONCURRENT_COUNT;
        _managerLock = dispatch_semaphore_create(1);
        
        [self startMemoryMonitoring];
        [self setupMemoryWarningNotification];
    }
    return self;
}

- (void)dealloc {
    [_memoryMonitorTimer invalidate];
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

#pragma mark - Public Methods

- (void)registerAnimatedImageView:(YYAnimatedImageView *)imageView {
    if (!imageView) return;
    
    dispatch_semaphore_wait(_managerLock, DISPATCH_TIME_FOREVER);
    [_registeredViews addObject:imageView];
    dispatch_semaphore_signal(_managerLock);
    
    // 立即计算并设置该视图的缓存大小
    [self updateBufferSizeForImageView:imageView];
}

- (void)unregisterAnimatedImageView:(YYAnimatedImageView *)imageView {
    if (!imageView) return;
    
    dispatch_semaphore_wait(_managerLock, DISPATCH_TIME_FOREVER);
    [_registeredViews removeObject:imageView];
    dispatch_semaphore_signal(_managerLock);
}

- (NSUInteger)recommendedMaxBufferSizeForImageView:(YYAnimatedImageView *)imageView {
    NSUInteger totalMemory = [self getAvailableMemory];
    NSUInteger registeredCount = _registeredViews.count;
    
    if (registeredCount == 0) {
        return MINIMUM_BUFFER_SIZE * 4; // 如果只有一个，给多一些
    }
    
    // 根据内存情况和注册的视图数量分配缓存
    NSUInteger baseAllocation = totalMemory / registeredCount;
    NSUInteger minAllocation = MINIMUM_BUFFER_SIZE;
    NSUInteger maxAllocation = totalMemory * 0.3; // 单个视图最多占用30%的可用内存
    
    NSUInteger allocation = MAX(minAllocation, MIN(baseAllocation, maxAllocation));
    
    // 根据CPU使用情况调整
    double cpuUsage = [self getCurrentCPUUsage];
    if (cpuUsage > 0.8) {
        // CPU使用率高，增加缓存减少解码
        allocation = allocation * 1.5;
    } else if (cpuUsage < 0.3) {
        // CPU使用率低，可以减少缓存
        allocation = allocation * 0.8;
    }
    
    return allocation;
}

- (NSOperationQueue *)globalDecodeQueue {
    return _globalDecodeQueue;
}

- (void)recalculateBufferSizes {
    dispatch_semaphore_wait(_managerLock, DISPATCH_TIME_FOREVER);
    NSSet *views = [_registeredViews copy];
    dispatch_semaphore_signal(_managerLock);
    
    for (YYAnimatedImageView *view in views) {
        [self updateBufferSizeForImageView:view];
    }
    
    [self adjustConcurrentOperationCount];
}

#pragma mark - Private Methods

- (void)updateBufferSizeForImageView:(YYAnimatedImageView *)imageView {
    NSUInteger recommendedSize = [self recommendedMaxBufferSizeForImageView:imageView];
    imageView.maxBufferSize = recommendedSize;
}

- (void)startMemoryMonitoring {
    _memoryMonitorTimer = [NSTimer scheduledTimerWithTimeInterval:MEMORY_CHECK_INTERVAL
                                                           target:self
                                                         selector:@selector(memoryMonitorTick:)
                                                         userInfo:nil
                                                          repeats:YES];
}

- (void)memoryMonitorTick:(NSTimer *)timer {
    NSUInteger currentMemory = [self getAvailableMemory];
    double currentCPU = [self getCurrentCPUUsage];
    
    // 如果内存或CPU使用情况有显著变化，重新计算缓存大小
    if (ABS((int64_t)currentMemory - (int64_t)_lastAvailableMemory) > (10 * 1024 * 1024) || // 内存变化超过10MB
        ABS(currentCPU - _lastCPUUsage) > 0.1) { // CPU使用率变化超过10%
        
        _lastAvailableMemory = currentMemory;
        _lastCPUUsage = currentCPU;
        
        [self recalculateBufferSizes];
    }
}

- (void)adjustConcurrentOperationCount {
    double cpuUsage = [self getCurrentCPUUsage];
    NSInteger newCount = DEFAULT_CONCURRENT_COUNT;
    
    if (cpuUsage > 0.8) {
        // CPU使用率高，减少并发
        newCount = 1;
    } else if (cpuUsage < 0.3) {
        // CPU使用率低，可以增加并发
        newCount = 4;
    } else {
        // 中等使用率，使用默认值
        newCount = DEFAULT_CONCURRENT_COUNT;
    }
    
    _globalDecodeQueue.maxConcurrentOperationCount = newCount;
}

- (void)setupMemoryWarningNotification {
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(didReceiveMemoryWarning:)
                                                 name:UIApplicationDidReceiveMemoryWarningNotification
                                               object:nil];
    
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(didEnterBackground:)
                                                 name:UIApplicationDidEnterBackgroundNotification
                                               object:nil];
}

- (void)didReceiveMemoryWarning:(NSNotification *)notification {
    // 内存警告时，显著减少所有视图的缓存大小
    dispatch_semaphore_wait(_managerLock, DISPATCH_TIME_FOREVER);
    NSSet *views = [_registeredViews copy];
    dispatch_semaphore_signal(_managerLock);
    
    for (YYAnimatedImageView *view in views) {
        view.maxBufferSize = MINIMUM_BUFFER_SIZE;
    }
    
    // 减少并发数
    _globalDecodeQueue.maxConcurrentOperationCount = 1;
}

- (void)didEnterBackground:(NSNotification *)notification {
    // 进入后台时，最小化内存使用
    [self didReceiveMemoryWarning:notification];
}

#pragma mark - System Info

- (NSUInteger)getAvailableMemory {
    mach_port_t host_port = mach_host_self();
    mach_msg_type_number_t host_size = sizeof(vm_statistics_data_t) / sizeof(integer_t);
    vm_size_t page_size;
    vm_statistics_data_t vm_stat;
    kern_return_t kern;
    
    kern = host_page_size(host_port, &page_size);
    if (kern != KERN_SUCCESS) return MINIMUM_BUFFER_SIZE * 2;
    
    kern = host_statistics(host_port, HOST_VM_INFO, (host_info_t)&vm_stat, &host_size);
    if (kern != KERN_SUCCESS) return MINIMUM_BUFFER_SIZE * 2;
    
    NSUInteger freeMemory = vm_stat.free_count * page_size;
    NSUInteger totalMemory = [[NSProcessInfo processInfo] physicalMemory];
    
    // 可用内存 = 空闲内存 + 部分已用内存的安全比例
    NSUInteger availableMemory = freeMemory + (totalMemory * 0.1); // 假设可以使用10%的已用内存
    
    return availableMemory;
}

- (double)getCurrentCPUUsage {
    kern_return_t kr;
    task_info_data_t tinfo;
    mach_msg_type_number_t task_info_count;
    
    task_info_count = TASK_INFO_MAX;
    kr = task_info(mach_task_self(), TASK_BASIC_INFO, (task_info_t)tinfo, &task_info_count);
    if (kr != KERN_SUCCESS) {
        return 0.0;
    }
    
    thread_array_t thread_list;
    mach_msg_type_number_t thread_count;
    
    kr = task_threads(mach_task_self(), &thread_list, &thread_count);
    if (kr != KERN_SUCCESS) {
        return 0.0;
    }
    
    long tot_sec = 0;
    long tot_usec = 0;
    float tot_cpu = 0;
    
    for (int j = 0; j < thread_count; j++) {
        thread_info_data_t thinfo;
        mach_msg_type_number_t thread_info_count = THREAD_INFO_MAX;
        kr = thread_info(thread_list[j], THREAD_BASIC_INFO, (thread_info_t)thinfo, &thread_info_count);
        if (kr != KERN_SUCCESS) {
            continue;
        }
        
        thread_basic_info_t basic_info_th = (thread_basic_info_t)thinfo;
        
        if (!(basic_info_th->flags & TH_FLAGS_IDLE)) {
            tot_sec = tot_sec + basic_info_th->user_time.seconds + basic_info_th->system_time.seconds;
            tot_usec = tot_usec + basic_info_th->user_time.microseconds + basic_info_th->system_time.microseconds;
            tot_cpu = tot_cpu + basic_info_th->cpu_usage / (float)TH_USAGE_SCALE;
        }
    }
    
    kr = vm_deallocate(mach_task_self(), (vm_offset_t)thread_list, thread_count * sizeof(thread_t));
    
    return tot_cpu;
}

@end