#import <Foundation/Foundation.h>
#import "AnimationManager.h"
#import "SimpleAnimationPlayer.h"

void exampleUsage() {
    // 创建不同特征的动画播放器
    // 播放器1：小动画，低帧率，低优先级
    SimpleAnimationPlayer *player1 = [[SimpleAnimationPlayer alloc] 
        initWithAnimationPath:@"small_animation.gif" 
        frameSize:50*1024    // 50KB per frame
        frameRate:15];       // 15fps
    player1.priority = 3;    // 低优先级
    
    // 播放器2：高清动画，高帧率，高优先级
    SimpleAnimationPlayer *player2 = [[SimpleAnimationPlayer alloc] 
        initWithAnimationPath:@"hd_animation.gif" 
        frameSize:500*1024   // 500KB per frame
        frameRate:60];       // 60fps
    player2.priority = 8;    // 高优先级
    
    // 播放器3：普通动画，正常帧率，中等优先级
    SimpleAnimationPlayer *player3 = [[SimpleAnimationPlayer alloc] 
        initWithAnimationPath:@"normal_animation.gif"
        frameSize:100*1024   // 100KB per frame
        frameRate:30];       // 30fps
    player3.priority = 5;    // 中等优先级
    
    // 开始播放
    [player1 startPlaying];
    [player2 startPlaying];
    [player3 startPlaying];
    
    // 全局管理器会根据每个播放器的特征智能分配缓存：
    // - player2 (高优先级+高帧率+大帧) 会获得更多缓存
    // - player1 (低优先级+低帧率+小帧) 会获得较少缓存
    // - player3 (中等配置) 会获得适中的缓存
    
    // 内存充足时：总缓存池200MB，根据权重分配
    // 内存警告时：总缓存池60-100MB，根据CPU负载调整
    // 内存不足时：总缓存池30MB，确保最小运行需求
    
    // 可以通过管理器获取所有播放器
    NSArray *allPlayers = [[AnimationManager sharedManager] allPlayers];
    NSLog(@"当前有 %lu 个播放器", (unsigned long)allPlayers.count);
    
    // 动态调整优先级
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        // 提升player1的优先级
        player1.priority = 9;
        // 触发缓存重新分配
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
        
        // 此时播放器才会被真正释放
        NSLog(@"播放器已注销，当前剩余 %lu 个播放器", 
              (unsigned long)[[AnimationManager sharedManager] allPlayers].count);
    });
}