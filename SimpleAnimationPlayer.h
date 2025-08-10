#import <Foundation/Foundation.h>
#import "AnimationManager.h"

NS_ASSUME_NONNULL_BEGIN

@interface SimpleAnimationPlayer : NSObject <AnimationPlayerProtocol>

@property (nonatomic, strong, readonly) NSString *animationPath;
@property (nonatomic, strong, readonly) NSMutableData *frameBuffer;

- (instancetype)initWithAnimationPath:(NSString *)path;
- (instancetype)initWithAnimationPath:(NSString *)path frameSize:(NSUInteger)frameSize frameRate:(NSUInteger)frameRate;
- (void)startPlaying;
- (void)stopPlaying;

@end

NS_ASSUME_NONNULL_END