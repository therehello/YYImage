#import <Foundation/Foundation.h>
#import "AnimationManager.h"
#import "SimpleAnimationPlayer.h"

void exampleUsage() {
    // 创建不同特征的动画播放器
    // 播放器1：小动画，低帧率
    SimpleAnimationPlayer *player1 = [[SimpleAnimationPlayer alloc] 
        initWithAnimationPath:@"small_animation.gif" 
        frameSize:50*1024    // 50KB per frame
        frameRate:15];       // 15fps
    
    // 播放器2：高清动画，高帧率
    SimpleAnimationPlayer *player2 = [[SimpleAnimationPlayer alloc] 
        initWithAnimationPath:@"hd_animation.gif" 
        frameSize:500*1024   // 500KB per frame
        frameRate:60];       // 60fps
    
    // 播放器3：普通动画，正常帧率
    SimpleAnimationPlayer *player3 = [[SimpleAnimationPlayer alloc] 
        initWithAnimationPath:@"normal_animation.gif"
        frameSize:100*1024   // 100KB per frame
        frameRate:30];       // 30fps
    
    // 开始播放
    [player1 startPlaying];
    [player2 startPlaying];
    [player3 startPlaying];
    
    // 渐进式缓存分配策略：
    // 1. 初始阶段：即使内存充足，也不会立即分配大量缓存
    //    - 总缓存池从100MB开始（而不是一开始就200MB）
    //    - 每个播放器根据特征获得初始配额
    //
    // 2. 动态增长：
    //    - 只有当播放器缓存使用率超过70%时，才会增加缓存
    //    - 每次增长50%，避免突然占用大量内存
    //
    // 3. 收缩机制：
    //    - 当总使用接近上限90%时，逐步减少各播放器缓存
    //    - 每次减少20%，平滑过渡
    //
    // 4. 边界保护：
    //    - 最小缓存：确保至少能存储5-10帧
    //    - 最大缓存：单个播放器不超过30MB（内存充足时）
    
    NSLog(@"渐进式缓存分配已启动，避免内存突然大量占用");
    
    // 可以通过管理器获取所有播放器
    NSArray *allPlayers = [[AnimationManager sharedManager] allPlayers];
    NSLog(@"当前有 %lu 个播放器", (unsigned long)allPlayers.count);
    
    // 模拟一段时间后的情况
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        NSLog(@"5秒后，缓存会根据实际使用情况自动调整");
        [[AnimationManager sharedManager] updateCacheStrategy];
    });
    
    // 停止播放并释放播放器
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(10 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [player1 stopPlaying];
        [player2 stopPlaying];
        [player3 stopPlaying];
        
        // 重要：由于管理器持有强引用，需要手动注销播放器才能释放内存
        [[AnimationManager sharedManager] unregisterPlayer:player1];
        [[AnimationManager sharedManager] unregisterPlayer:player2];
        [[AnimationManager sharedManager] unregisterPlayer:player3];
        
        NSLog(@"播放器已注销，内存已释放");
    });
}