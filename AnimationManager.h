#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@protocol AnimationPlayerProtocol <NSObject>
@property (nonatomic, assign) NSUInteger maxBufferSize;
@property (nonatomic, assign, readonly) NSUInteger currentBufferSize;  // 当前缓存大小
@property (nonatomic, assign, readonly) NSUInteger frameSize;         // 单帧大小
@property (nonatomic, assign, readonly) NSUInteger frameRate;         // 帧率
@property (nonatomic, assign) NSUInteger priority;                    // 优先级 (0-10, 10最高)

- (void)updateMaxBufferSize:(NSUInteger)newSize;
@end

typedef NS_ENUM(NSUInteger, MemoryPressureLevel) {
    MemoryPressureLevelNormal = 0,    // 内存充足
    MemoryPressureLevelWarning = 1,   // 内存警告
    MemoryPressureLevelCritical = 2   // 内存严重不足
};

typedef NS_ENUM(NSUInteger, CPULoadLevel) {
    CPULoadLevelLow = 0,     // CPU负载低
    CPULoadLevelMedium = 1,  // CPU负载中等
    CPULoadLevelHigh = 2     // CPU负载高
};

@interface AnimationManager : NSObject

+ (instancetype)sharedManager;

// 获取所有播放器
@property (nonatomic, strong, readonly) NSArray<id<AnimationPlayerProtocol>> *allPlayers;

// 注册和注销播放器
- (void)registerPlayer:(id<AnimationPlayerProtocol>)player;
- (void)unregisterPlayer:(id<AnimationPlayerProtocol>)player;

// 解码任务管理
- (void)submitDecodeTask:(NSOperation *)task forPlayer:(id<AnimationPlayerProtocol>)player;

// 手动触发缓存策略更新
- (void)updateCacheStrategy;

@end

NS_ASSUME_NONNULL_END