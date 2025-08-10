//
//  YYAnimatedImageCacheManagerDemo.m
//  YYImage Demo
//
//  Created by ibireme on 14/10/19.
//  Copyright (c) 2015 ibireme.
//
//  This source code is licensed under the MIT-style license found in the
//  LICENSE file in the root directory of this source tree.
//

#import "YYAnimatedImageCacheManagerDemo.h"
#import "YYAnimatedImageView.h"
#import "YYImage.h"
#import "YYAnimatedImageCacheManager.h"

@interface YYAnimatedImageCacheManagerDemo ()
@property (nonatomic, strong) YYAnimatedImageView *animatedImageView1;
@property (nonatomic, strong) YYAnimatedImageView *animatedImageView2;
@property (nonatomic, strong) YYAnimatedImageView *animatedImageView3;
@property (nonatomic, strong) UILabel *statusLabel;
@end

@implementation YYAnimatedImageCacheManagerDemo

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor whiteColor];
    
    // 设置全局缓存管理器参数
    YYAnimatedImageCacheManager *cacheManager = [YYAnimatedImageCacheManager sharedManager];
    cacheManager.memoryWarningReductionRatio = 0.5; // 内存警告时减少50%
    cacheManager.memorySufficientGrowthRatio = 1.2; // 内存充足时增长20%
    cacheManager.memoryWarningMinInterval = 30.0; // 内存警告最小间隔30秒
    cacheManager.memorySufficientCheckInterval = 60.0; // 内存充足检查间隔60秒
    
    [self setupUI];
    [self loadAnimatedImages];
    [self updateStatusLabel];
    
    // 定时更新状态显示
    [NSTimer scheduledTimerWithTimeInterval:2.0 target:self selector:@selector(updateStatusLabel) userInfo:nil repeats:YES];
}

- (void)setupUI {
    // 创建状态标签
    self.statusLabel = [[UILabel alloc] init];
    self.statusLabel.numberOfLines = 0;
    self.statusLabel.font = [UIFont systemFontOfSize:12];
    self.statusLabel.textColor = [UIColor darkGrayColor];
    self.statusLabel.backgroundColor = [UIColor colorWithWhite:0.95 alpha:1.0];
    self.statusLabel.layer.cornerRadius = 5;
    self.statusLabel.layer.masksToBounds = YES;
    [self.view addSubview:self.statusLabel];
    
    // 创建动图视图
    self.animatedImageView1 = [[YYAnimatedImageView alloc] init];
    self.animatedImageView1.animatedImageId = @"animated_image_1";
    self.animatedImageView1.contentMode = UIViewContentModeScaleAspectFit;
    self.animatedImageView1.layer.borderWidth = 1;
    self.animatedImageView1.layer.borderColor = [UIColor lightGrayColor].CGColor;
    [self.view addSubview:self.animatedImageView1];
    
    self.animatedImageView2 = [[YYAnimatedImageView alloc] init];
    self.animatedImageView2.animatedImageId = @"animated_image_2";
    self.animatedImageView2.contentMode = UIViewContentModeScaleAspectFit;
    self.animatedImageView2.layer.borderWidth = 1;
    self.animatedImageView2.layer.borderColor = [UIColor lightGrayColor].CGColor;
    [self.view addSubview:self.animatedImageView2];
    
    self.animatedImageView3 = [[YYAnimatedImageView alloc] init];
    self.animatedImageView3.animatedImageId = @"animated_image_3";
    self.animatedImageView3.contentMode = UIViewContentModeScaleAspectFit;
    self.animatedImageView3.layer.borderWidth = 1;
    self.animatedImageView3.layer.borderColor = [UIColor lightGrayColor].CGColor;
    [self.view addSubview:self.animatedImageView3];
    
    // 设置布局
    CGFloat screenWidth = self.view.bounds.size.width;
    CGFloat screenHeight = self.view.bounds.size.height;
    CGFloat statusHeight = 120;
    CGFloat imageHeight = (screenHeight - statusHeight - 100) / 3;
    
    self.statusLabel.frame = CGRectMake(10, 50, screenWidth - 20, statusHeight);
    self.animatedImageView1.frame = CGRectMake(10, 50 + statusHeight + 10, screenWidth - 20, imageHeight);
    self.animatedImageView2.frame = CGRectMake(10, 50 + statusHeight + 10 + imageHeight + 10, screenWidth - 20, imageHeight);
    self.animatedImageView3.frame = CGRectMake(10, 50 + statusHeight + 10 + (imageHeight + 10) * 2, screenWidth - 20, imageHeight);
}

- (void)loadAnimatedImages {
    // 加载动图（这里使用示例图片，实际使用时需要替换为真实的动图文件）
    // 注意：这里只是示例，实际使用时需要提供真实的动图文件
    
    // 示例1：加载一个小的动图
    // self.animatedImageView1.image = [YYImage imageNamed:@"small_animation"];
    
    // 示例2：加载一个中等大小的动图
    // self.animatedImageView2.image = [YYImage imageNamed:@"medium_animation"];
    
    // 示例3：加载一个大的动图
    // self.animatedImageView3.image = [YYImage imageNamed:@"large_animation"];
    
    // 开始播放动画
    [self.animatedImageView1 startAnimating];
    [self.animatedImageView2 startAnimating];
    [self.animatedImageView3 startAnimating];
}

- (void)updateStatusLabel {
    YYAnimatedImageCacheManager *cacheManager = [YYAnimatedImageCacheManager sharedManager];
    
    NSString *statusText = [NSString stringWithFormat:
                           @"全局缓存状态:\n"
                           @"最大缓存大小: %.1f MB\n"
                           @"当前使用: %.1f MB\n"
                           @"可用缓存: %.1f MB\n"
                           @"使用率: %.1f%%\n"
                           @"动图1缓存帧数: %lu\n"
                           @"动图2缓存帧数: %lu\n"
                           @"动图3缓存帧数: %lu",
                           cacheManager.maxCacheSize / (1024.0 * 1024.0),
                           cacheManager.usedCacheSize / (1024.0 * 1024.0),
                           cacheManager.availableCacheSize / (1024.0 * 1024.0),
                           (cacheManager.usedCacheSize * 100.0) / cacheManager.maxCacheSize,
                           (unsigned long)[cacheManager suggestedCacheFrameCount:@"animated_image_1"],
                           (unsigned long)[cacheManager suggestedCacheFrameCount:@"animated_image_2"],
                           (unsigned long)[cacheManager suggestedCacheFrameCount:@"animated_image_3"]];
    
    self.statusLabel.text = statusText;
}

// 模拟内存警告（用于测试）
- (void)simulateMemoryWarning {
    [[YYAnimatedImageCacheManager sharedManager] handleMemoryWarning];
    [self updateStatusLabel];
}

@end