//
//  YYGlobalAnimatedImageManager.h
//  YYImage <https://github.com/ibireme/YYImage>
//
//  Created by Global Manager on 2024/12/19.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@class YYAnimatedImageView;

/**
 全局动图管理器
 
 负责统一管理所有动图的内存分配和CPU使用策略
 - 根据系统内存情况动态调整每个player的缓存大小
 - 根据CPU负载调整解码任务的并发数量
 - 提供全局的解码任务调度
 */
@interface YYGlobalAnimatedImageManager : NSObject

/// 单例实例
+ (instancetype)sharedManager;

/// 注册一个动图视图，开始管理其缓存
- (void)registerAnimatedImageView:(YYAnimatedImageView *)imageView;

/// 注销一个动图视图，停止管理其缓存
- (void)unregisterAnimatedImageView:(YYAnimatedImageView *)imageView;

/// 获取指定视图当前建议的最大缓存大小（字节）
- (NSUInteger)recommendedMaxBufferSizeForImageView:(YYAnimatedImageView *)imageView;

/// 获取全局解码操作队列
- (NSOperationQueue *)globalDecodeQueue;

/// 手动触发重新计算所有视图的缓存大小（通常由系统内存变化触发）
- (void)recalculateBufferSizes;

@end

NS_ASSUME_NONNULL_END