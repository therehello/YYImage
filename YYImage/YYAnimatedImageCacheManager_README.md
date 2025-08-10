# YYAnimatedImageCacheManager 全局动图缓存管理器

## 概述

`YYAnimatedImageCacheManager` 是一个全局的动图缓存管理类，用于管理应用中所有动图的缓存大小。它提供了智能的内存管理机制，能够根据设备内存状况动态调整缓存策略，避免内存溢出。

## 主要特性

- **全局缓存管理**：统一管理所有动图的缓存大小
- **智能内存调整**：根据内存警告和内存充足情况动态调整缓存大小
- **防频繁触发**：记录上次内存警告时间，避免频繁触发缓存清理
- **定时检查**：定期检查内存状况，在内存充足时扩大缓存
- **线程安全**：使用信号量保证多线程环境下的数据安全

## 使用方法

### 1. 基本使用

```objc
// 获取全局缓存管理器实例
YYAnimatedImageCacheManager *cacheManager = [YYAnimatedImageCacheManager sharedManager];

// 设置缓存参数（可选）
cacheManager.memoryWarningReductionRatio = 0.5; // 内存警告时减少50%
cacheManager.memorySufficientGrowthRatio = 1.2; // 内存充足时增长20%
cacheManager.memoryWarningMinInterval = 30.0; // 内存警告最小间隔30秒
cacheManager.memorySufficientCheckInterval = 60.0; // 内存充足检查间隔60秒
```

### 2. 在 YYAnimatedImageView 中使用

```objc
// 创建动图视图并设置唯一标识符
YYAnimatedImageView *animatedImageView = [[YYAnimatedImageView alloc] init];
animatedImageView.animatedImageId = @"unique_image_id";
animatedImageView.image = [YYImage imageNamed:@"animation"];

// 开始播放动画
[animatedImageView startAnimating];
```

### 3. 手动管理缓存

```objc
// 注册动图缓存信息
[cacheManager registerAnimatedImage:@"image_id" 
                         frameSize:1024 
                        frameCount:30];

// 更新缓存使用情况
[cacheManager updateAnimatedImageCache:@"image_id" 
                      cachedFrameCount:5];

// 检查是否可以缓存更多帧
BOOL canCache = [cacheManager canCacheMoreFrames:@"image_id" 
                                additionalFrames:3];

// 获取建议的缓存帧数
NSUInteger suggestedFrames = [cacheManager suggestedCacheFrameCount:@"image_id"];

// 注销动图缓存
[cacheManager unregisterAnimatedImage:@"image_id"];

// 清理所有缓存
[cacheManager clearAllCache];
```

## 核心机制

### 1. 内存警告处理

当系统发出内存警告时，缓存管理器会：

1. 检查距离上次内存警告的时间间隔
2. 如果超过最小间隔时间，则按比例减少可用缓存大小
3. 如果当前使用量超过新的最大值，则清理多余的缓存
4. 记录本次内存警告时间

### 2. 内存充足检查

定时器会定期检查内存状况：

1. 检查距离上次内存警告的时间间隔
2. 如果超过检查间隔且可用内存充足（超过总内存的30%），则按比例扩大缓存大小
3. 缓存大小不会超过原始设置的最大值

### 3. 预加载帧管理

在预加载下一帧时：

1. 检查全局缓存是否足够
2. 如果不足，删除前两帧（保留当前帧和下一帧）
3. 更新全局缓存使用情况

## 配置参数

| 参数 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `maxCacheSize` | NSUInteger | 设备内存的20% | 最大缓存大小（字节） |
| `memoryWarningReductionRatio` | CGFloat | 0.5 | 内存警告后缓存减少比例 |
| `memorySufficientGrowthRatio` | CGFloat | 1.2 | 内存充足时缓存增长比例 |
| `memoryWarningMinInterval` | NSTimeInterval | 30.0 | 内存警告后最小间隔时间（秒） |
| `memorySufficientCheckInterval` | NSTimeInterval | 60.0 | 内存充足检查间隔时间（秒） |

## 性能优化建议

1. **合理设置标识符**：为每个动图设置唯一的、有意义的标识符，便于调试和监控
2. **监控缓存状态**：定期检查 `usedCacheSize` 和 `availableCacheSize` 来了解缓存使用情况
3. **调整参数**：根据应用的具体需求调整缓存参数，平衡性能和内存使用
4. **及时注销**：在动图视图销毁时及时注销缓存，避免内存泄漏

## 注意事项

1. 缓存管理器是单例模式，全局共享
2. 所有操作都是线程安全的
3. 内存警告处理有最小间隔限制，避免频繁触发
4. 缓存大小会根据设备内存状况动态调整
5. 建议在应用启动时配置缓存参数

## 示例代码

完整的使用示例请参考 `Demo/YYAnimatedImageCacheManagerDemo.m` 文件。