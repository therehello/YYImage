//
//  YYAnimatedImageCacheManagerTests.m
//  YYImage Tests
//
//  Created by ibireme on 14/10/19.
//  Copyright (c) 2015 ibireme.
//
//  This source code is licensed under the MIT-style license found in the
//  LICENSE file in the root directory of this source tree.
//

#import <XCTest/XCTest.h>
#import "YYAnimatedImageCacheManager.h"

@interface YYAnimatedImageCacheManagerTests : XCTestCase
@property (nonatomic, strong) YYAnimatedImageCacheManager *cacheManager;
@end

@implementation YYAnimatedImageCacheManagerTests

- (void)setUp {
    [super setUp];
    self.cacheManager = [YYAnimatedImageCacheManager sharedManager];
    
    // 清理所有缓存
    [self.cacheManager clearAllCache];
}

- (void)tearDown {
    [self.cacheManager clearAllCache];
    [super tearDown];
}

- (void)testSingleton {
    YYAnimatedImageCacheManager *manager1 = [YYAnimatedImageCacheManager sharedManager];
    YYAnimatedImageCacheManager *manager2 = [YYAnimatedImageCacheManager sharedManager];
    
    XCTAssertEqual(manager1, manager2, @"Singleton should return the same instance");
}

- (void)testRegisterAndUnregisterAnimatedImage {
    NSString *imageId = @"test_image";
    NSUInteger frameSize = 1024;
    NSUInteger frameCount = 30;
    
    // 注册动图
    [self.cacheManager registerAnimatedImage:imageId frameSize:frameSize frameCount:frameCount];
    
    // 检查是否可以缓存帧
    XCTAssertTrue([self.cacheManager canCacheMoreFrames:imageId additionalFrames:1], @"Should be able to cache frames after registration");
    
    // 注销动图
    [self.cacheManager unregisterAnimatedImage:imageId];
    
    // 检查是否无法缓存帧
    XCTAssertFalse([self.cacheManager canCacheMoreFrames:imageId additionalFrames:1], @"Should not be able to cache frames after unregistration");
}

- (void)testUpdateCacheUsage {
    NSString *imageId = @"test_image";
    NSUInteger frameSize = 1024;
    NSUInteger frameCount = 30;
    
    // 注册动图
    [self.cacheManager registerAnimatedImage:imageId frameSize:frameSize frameCount:frameCount];
    
    // 初始使用量应该为0
    XCTAssertEqual(self.cacheManager.usedCacheSize, 0, @"Initial used cache size should be 0");
    
    // 更新缓存使用情况
    [self.cacheManager updateAnimatedImageCache:imageId cachedFrameCount:5];
    
    // 检查使用量是否正确更新
    NSUInteger expectedUsedSize = 5 * frameSize;
    XCTAssertEqual(self.cacheManager.usedCacheSize, expectedUsedSize, @"Used cache size should be updated correctly");
    
    // 再次更新
    [self.cacheManager updateAnimatedImageCache:imageId cachedFrameCount:10];
    
    // 检查使用量是否正确更新
    expectedUsedSize = 10 * frameSize;
    XCTAssertEqual(self.cacheManager.usedCacheSize, expectedUsedSize, @"Used cache size should be updated correctly");
}

- (void)testCanCacheMoreFrames {
    NSString *imageId = @"test_image";
    NSUInteger frameSize = 1024;
    NSUInteger frameCount = 30;
    
    // 注册动图
    [self.cacheManager registerAnimatedImage:imageId frameSize:frameSize frameCount:frameCount];
    
    // 设置一个小的最大缓存大小
    NSUInteger smallMaxCacheSize = frameSize * 5; // 只能缓存5帧
    self.cacheManager.maxCacheSize = smallMaxCacheSize;
    
    // 应该可以缓存5帧
    XCTAssertTrue([self.cacheManager canCacheMoreFrames:imageId additionalFrames:5], @"Should be able to cache 5 frames");
    
    // 不应该可以缓存6帧
    XCTAssertFalse([self.cacheManager canCacheMoreFrames:imageId additionalFrames:6], @"Should not be able to cache 6 frames");
    
    // 更新缓存使用情况
    [self.cacheManager updateAnimatedImageCache:imageId cachedFrameCount:3];
    
    // 现在只能缓存2帧
    XCTAssertTrue([self.cacheManager canCacheMoreFrames:imageId additionalFrames:2], @"Should be able to cache 2 more frames");
    XCTAssertFalse([self.cacheManager canCacheMoreFrames:imageId additionalFrames:3], @"Should not be able to cache 3 more frames");
}

- (void)testSuggestedCacheFrameCount {
    NSString *imageId = @"test_image";
    NSUInteger frameSize = 1024;
    NSUInteger frameCount = 30;
    
    // 注册动图
    [self.cacheManager registerAnimatedImage:imageId frameSize:frameSize frameCount:frameCount];
    
    // 设置最大缓存大小
    NSUInteger maxCacheSize = frameSize * 20; // 可以缓存20帧
    self.cacheManager.maxCacheSize = maxCacheSize;
    
    // 获取建议的缓存帧数
    NSUInteger suggestedFrames = [self.cacheManager suggestedCacheFrameCount:imageId];
    
    // 建议帧数应该不超过总帧数和最大可缓存帧数
    XCTAssertLessThanOrEqual(suggestedFrames, frameCount, @"Suggested frames should not exceed total frame count");
    XCTAssertLessThanOrEqual(suggestedFrames, 20, @"Suggested frames should not exceed max cacheable frames");
}

- (void)testMemoryWarningHandling {
    NSString *imageId = @"test_image";
    NSUInteger frameSize = 1024;
    NSUInteger frameCount = 30;
    
    // 注册动图
    [self.cacheManager registerAnimatedImage:imageId frameSize:frameSize frameCount:frameCount];
    
    // 设置初始最大缓存大小
    NSUInteger initialMaxCacheSize = frameSize * 100;
    self.cacheManager.maxCacheSize = initialMaxCacheSize;
    
    // 记录初始可用缓存大小
    NSUInteger initialAvailableSize = self.cacheManager.availableCacheSize;
    
    // 模拟内存警告
    [self.cacheManager handleMemoryWarning];
    
    // 检查缓存大小是否减少
    NSUInteger newAvailableSize = self.cacheManager.availableCacheSize;
    XCTAssertLessThan(newAvailableSize, initialAvailableSize, @"Available cache size should be reduced after memory warning");
}

- (void)testClearAllCache {
    NSString *imageId1 = @"test_image_1";
    NSString *imageId2 = @"test_image_2";
    NSUInteger frameSize = 1024;
    
    // 注册两个动图
    [self.cacheManager registerAnimatedImage:imageId1 frameSize:frameSize frameCount:30];
    [self.cacheManager registerAnimatedImage:imageId2 frameSize:frameSize frameCount:20];
    
    // 更新缓存使用情况
    [self.cacheManager updateAnimatedImageCache:imageId1 cachedFrameCount:10];
    [self.cacheManager updateAnimatedImageCache:imageId2 cachedFrameCount:5];
    
    // 检查使用量不为0
    XCTAssertGreaterThan(self.cacheManager.usedCacheSize, 0, @"Used cache size should be greater than 0");
    
    // 清理所有缓存
    [self.cacheManager clearAllCache];
    
    // 检查使用量是否为0
    XCTAssertEqual(self.cacheManager.usedCacheSize, 0, @"Used cache size should be 0 after clearing all cache");
}

- (void)testMultipleImagesCacheManagement {
    NSString *imageId1 = @"test_image_1";
    NSString *imageId2 = @"test_image_2";
    NSString *imageId3 = @"test_image_3";
    NSUInteger frameSize = 1024;
    
    // 注册三个动图
    [self.cacheManager registerAnimatedImage:imageId1 frameSize:frameSize frameCount:30];
    [self.cacheManager registerAnimatedImage:imageId2 frameSize:frameSize frameCount:20];
    [self.cacheManager registerAnimatedImage:imageId3 frameSize:frameSize frameCount:15];
    
    // 设置较小的最大缓存大小
    NSUInteger maxCacheSize = frameSize * 25; // 总共只能缓存25帧
    self.cacheManager.maxCacheSize = maxCacheSize;
    
    // 更新缓存使用情况
    [self.cacheManager updateAnimatedImageCache:imageId1 cachedFrameCount:10];
    [self.cacheManager updateAnimatedImageCache:imageId2 cachedFrameCount:8];
    [self.cacheManager updateAnimatedImageCache:imageId3 cachedFrameCount:7];
    
    // 检查总使用量
    NSUInteger totalUsedSize = (10 + 8 + 7) * frameSize;
    XCTAssertEqual(self.cacheManager.usedCacheSize, totalUsedSize, @"Total used cache size should be correct");
    
    // 检查每个动图是否可以缓存更多帧
    XCTAssertTrue([self.cacheManager canCacheMoreFrames:imageId1 additionalFrames:1], @"Image 1 should be able to cache more frames");
    XCTAssertTrue([self.cacheManager canCacheMoreFrames:imageId2 additionalFrames:1], @"Image 2 should be able to cache more frames");
    XCTAssertTrue([self.cacheManager canCacheMoreFrames:imageId3 additionalFrames:1], @"Image 3 should be able to cache more frames");
    
    // 注销一个动图
    [self.cacheManager unregisterAnimatedImage:imageId2];
    
    // 检查总使用量是否减少
    NSUInteger newTotalUsedSize = (10 + 7) * frameSize;
    XCTAssertEqual(self.cacheManager.usedCacheSize, newTotalUsedSize, @"Total used cache size should be reduced after unregistration");
}

@end