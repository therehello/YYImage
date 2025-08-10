#import <Foundation/Foundation.h>
#import "AnimationManager.h"
#import "SimpleAnimationPlayer.h"

void exampleUsage() {
    // 创建多个动画播放器
    SimpleAnimationPlayer *player1 = [[SimpleAnimationPlayer alloc] initWithAnimationPath:@"animation1.gif"];
    SimpleAnimationPlayer *player2 = [[SimpleAnimationPlayer alloc] initWithAnimationPath:@"animation2.gif"];
    SimpleAnimationPlayer *player3 = [[SimpleAnimationPlayer alloc] initWithAnimationPath:@"animation3.gif"];
    
    // 开始播放
    [player1 startPlaying];
    [player2 startPlaying];
    [player3 startPlaying];
    
    // 全局管理器会自动监控系统资源并调整每个播放器的缓存大小
    // 内存充足时：每个播放器分配较大缓存（如50MB）
    // 内存不足时：根据CPU负载动态调整
    //   - CPU负载高：增加缓存减少解码（如20MB）
    //   - CPU负载低：减少缓存增加并发解码（如10MB）
    
    // 手动触发缓存策略更新（通常不需要，管理器会自动定时更新）
    [[AnimationManager sharedManager] updateCacheStrategy];
    
    // 停止播放
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(10 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [player1 stopPlaying];
        [player2 stopPlaying];
        [player3 stopPlaying];
    });
}