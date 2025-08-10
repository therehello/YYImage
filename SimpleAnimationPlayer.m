#import "SimpleAnimationPlayer.h"

@interface SimpleAnimationPlayer ()

@property (nonatomic, strong, readwrite) NSString *animationPath;
@property (nonatomic, strong, readwrite) NSMutableData *frameBuffer;
@property (nonatomic, assign) NSUInteger maxBufferSize;
@property (nonatomic, assign) BOOL isPlaying;

@end

@implementation SimpleAnimationPlayer

- (instancetype)initWithAnimationPath:(NSString *)path {
    self = [super init];
    if (self) {
        _animationPath = path;
        _frameBuffer = [NSMutableData data];
        _maxBufferSize = 10 * 1024 * 1024; // 默认10MB
        
        // 注册到全局管理器
        [[AnimationManager sharedManager] registerPlayer:self];
    }
    return self;
}

- (void)dealloc {
    // 注销
    [[AnimationManager sharedManager] unregisterPlayer:self];
}

- (void)startPlaying {
    self.isPlaying = YES;
    [self decodeNextFrame];
}

- (void)stopPlaying {
    self.isPlaying = NO;
}

- (void)decodeNextFrame {
    if (!self.isPlaying) return;
    
    // 创建解码任务
    NSOperation *decodeOperation = [NSBlockOperation blockOperationWithBlock:^{
        // 模拟解码过程
        NSData *frameData = [self simulateFrameDecode];
        
        // 在主线程更新缓存
        [[NSOperationQueue mainQueue] addOperationWithBlock:^{
            [self addFrameToBuffer:frameData];
            
            // 继续解码下一帧
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.033 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                [self decodeNextFrame];
            });
        }];
    }];
    
    // 提交解码任务到全局管理器
    [[AnimationManager sharedManager] submitDecodeTask:decodeOperation forPlayer:self];
}

- (NSData *)simulateFrameDecode {
    // 模拟生成一帧数据
    NSUInteger frameSize = 100 * 1024; // 100KB per frame
    NSMutableData *frameData = [NSMutableData dataWithLength:frameSize];
    uint8_t *bytes = (uint8_t *)frameData.mutableBytes;
    for (NSUInteger i = 0; i < frameSize; i++) {
        bytes[i] = arc4random_uniform(256);
    }
    return frameData;
}

- (void)addFrameToBuffer:(NSData *)frameData {
    // 检查缓存大小
    while (self.frameBuffer.length + frameData.length > self.maxBufferSize && self.frameBuffer.length > 0) {
        // 移除最早的帧（简单实现：移除前100KB）
        NSUInteger removeSize = MIN(100 * 1024, self.frameBuffer.length);
        [self.frameBuffer replaceBytesInRange:NSMakeRange(0, removeSize) withBytes:NULL length:0];
    }
    
    // 添加新帧
    [self.frameBuffer appendData:frameData];
    
    NSLog(@"Player %p: Buffer size: %.2fMB / %.2fMB", 
          self, 
          self.frameBuffer.length / 1024.0 / 1024.0,
          self.maxBufferSize / 1024.0 / 1024.0);
}

#pragma mark - AnimationPlayerProtocol

- (void)updateMaxBufferSize:(NSUInteger)newSize {
    self.maxBufferSize = newSize;
    
    // 如果当前缓存超过新的限制，清理部分缓存
    if (self.frameBuffer.length > newSize) {
        NSUInteger removeSize = self.frameBuffer.length - newSize;
        [self.frameBuffer replaceBytesInRange:NSMakeRange(0, removeSize) withBytes:NULL length:0];
    }
    
    NSLog(@"Player %p: Max buffer size updated to %.2fMB", self, newSize / 1024.0 / 1024.0);
}

@end