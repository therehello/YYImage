//
//  YYAnimatedImageCacheManager.h
//  YYImage <https://github.com/ibireme/YYImage>
//
//  Created by ibireme on 14/10/19.
//  Copyright (c) 2015 ibireme.
//
//  This source code is licensed under the MIT-style license found in the
//  LICENSE file in the root directory of this source tree.
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

/**
 全局动图缓存管理类
 
 负责管理所有动图的缓存大小，根据内存状况动态调整缓存策略
 */
@interface YYAnimatedImageCacheManager : NSObject

/**
 单例方法
 */
+ (instancetype)sharedManager;

/**
 当前可用的全局缓存大小（字节）
 */
@property (nonatomic, readonly) NSUInteger availableCacheSize;

/**
 当前已使用的缓存大小（字节）
 */
@property (nonatomic, readonly) NSUInteger usedCacheSize;

/**
 最大缓存大小（字节），默认值为设备内存的20%
 */
@property (nonatomic) NSUInteger maxCacheSize;

/**
 内存警告后缓存减少比例，默认0.5（减少50%）
 */
@property (nonatomic) CGFloat memoryWarningReductionRatio;

/**
 内存充足时缓存增长比例，默认1.2（增长20%）
 */
@property (nonatomic) CGFloat memorySufficientGrowthRatio;

/**
 内存警告后最小间隔时间（秒），默认30秒
 */
@property (nonatomic) NSTimeInterval memoryWarningMinInterval;

/**
 内存充足检查间隔时间（秒），默认60秒
 */
@property (nonatomic) NSTimeInterval memorySufficientCheckInterval;

/**
 注册动图缓存使用情况
 
 @param imageId 动图唯一标识
 @param frameSize 帧大小（字节）
 @param frameCount 帧数量
 */
- (void)registerAnimatedImage:(NSString *)imageId 
                   frameSize:(NSUInteger)frameSize 
                  frameCount:(NSUInteger)frameCount;

/**
 注销动图缓存使用情况
 
 @param imageId 动图唯一标识
 */
- (void)unregisterAnimatedImage:(NSString *)imageId;

/**
 更新动图缓存使用情况
 
 @param imageId 动图唯一标识
 @param cachedFrameCount 当前缓存的帧数量
 */
- (void)updateAnimatedImageCache:(NSString *)imageId 
                cachedFrameCount:(NSUInteger)cachedFrameCount;

/**
 检查是否可以缓存更多帧
 
 @param imageId 动图唯一标识
 @param additionalFrames 要缓存的额外帧数
 @return 是否可以缓存
 */
- (BOOL)canCacheMoreFrames:(NSString *)imageId 
           additionalFrames:(NSUInteger)additionalFrames;

/**
 获取动图建议的缓存帧数
 
 @param imageId 动图唯一标识
 @return 建议缓存的帧数
 */
- (NSUInteger)suggestedCacheFrameCount:(NSString *)imageId;

/**
 清理所有缓存
 */
- (void)clearAllCache;

/**
 手动触发内存警告处理（用于测试）
 */
- (void)handleMemoryWarning;

@end

NS_ASSUME_NONNULL_END