//
//  STLaunchAdView.m
//  STLaunchAdDemo
//
//  Created by sensetimesunjian on 2018/2/24.
//  Copyright © 2018年 sensetimesj. All rights reserved.
//

#import "STLaunchAdView.h"
#import "STLaunchAdConst.h"
#import "STLaunchImageView.h"

static NSString *const VideoPlayStatus = @"status";

@interface STLaunchAdImageView ()
@end

@implementation STLaunchAdImageView
- (id)init
{
    self = [super init];
    if (self) {
        self.userInteractionEnabled = YES;
        self.frame = [UIScreen mainScreen].bounds;
        self.layer.masksToBounds = YES;
        UITapGestureRecognizer *tapGesture = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(tap:)];
        [self addGestureRecognizer:tapGesture];
    }
    return self;
}

- (void)tap:(UIGestureRecognizer *)gestureRecognizer
{
    CGPoint point = [gestureRecognizer locationInView:self];
    if(self.click) self.click(point);
}

@end

#pragma mark - videoAdView
@interface STLaunchadVideoView ()<UIGestureRecognizerDelegate>
@property (nonatomic, strong) AVPlayerItem *playerItem;
@end

@implementation STLaunchadVideoView

- (void)dealloc
{
    [self.playerItem removeObserver:self forKeyPath:VideoPlayStatus];
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (instancetype)init
{
    self = [super init];
    if (self) {
        self.userInteractionEnabled = YES;
        self.backgroundColor = [UIColor clearColor];
        self.frame = [UIScreen mainScreen].bounds;
        [self addSubview:self.videoPlayer.view];
        UITapGestureRecognizer *tapGesture = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(tap:)];
        tapGesture.delegate = self;
        [self addGestureRecognizer:tapGesture];
    }
    return self;
}

- (void)tap:(UIGestureRecognizer *)gestureRecognizer
{
    CGPoint point = [gestureRecognizer locationInView:self];
    if(self.click) self.click(point);
}

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer shouldRecognizeSimultaneouslyWithGestureRecognizer:(nonnull UIGestureRecognizer *)otherGestureRecognizer
{
    return YES;
}

#pragma mark - Action
- (void)stopVideoPlayer
{
    if(nil == _videoPlayer) return;
    [_videoPlayer.player pause];
    [_videoPlayer.view removeFromSuperview];
    _videoPlayer = nil;
    
    //释放音频焦点
    [[AVAudioSession sharedInstance] setActive:NO withOptions:AVAudioSessionSetActiveOptionNotifyOthersOnDeactivation error:nil];
}

- (void)runLoopTheMovie:(NSNotification *)notification
{
    //需要循环播放
    if(!_videoCyclyOnce){
        [(AVPlayerItem *)[notification object] seekToTime:kCMTimeZero];
        [_videoPlayer.player play];//重播
    }
}

#pragma mark - KVO
- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary<NSKeyValueChangeKey,id> *)change context:(void *)context
{
    if ([keyPath isEqualToString:VideoPlayStatus]) {
        NSInteger newStatus = ((NSNumber *)change[@"new"]).integerValue;
        if (newStatus == AVPlayerItemStatusFailed) {
            [[NSNotificationCenter defaultCenter] postNotificationName:STLaunchAdVideoPlayFailedNotification object:nil userInfo:@{@"videoNameOrURLString":_contentURL.absoluteString}];
        }
    }
}

#pragma mark - lazy
- (AVPlayerViewController *)videoPlayer
{
    if (_videoPlayer == nil) {
        _videoPlayer = [[AVPlayerViewController alloc] init];
        _videoPlayer.showsPlaybackControls = NO;
        _videoPlayer.videoGravity = AVLayerVideoGravityResizeAspectFill;
        _videoPlayer.view.frame = [UIScreen mainScreen].bounds;
        _videoPlayer.view.backgroundColor = [UIColor clearColor];
        //注册通知控制是否循环播放
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(runLoopTheMovie:) name:AVPlayerItemDidPlayToEndTimeNotification object:nil];
        
        //获取音频焦点
        [[AVAudioSession sharedInstance] setCategory:AVAudioSessionCategoryPlayback error:nil];
        [[AVAudioSession sharedInstance] setActive:YES error:nil];
    }
    return _videoPlayer;
}

#pragma mark - set
- (void)setFrame:(CGRect)frame
{
    [super setFrame:frame];
    _videoPlayer.view.frame = self.frame;
}

- (void)setContentURL:(NSURL *)contentURL
{
    _contentURL = contentURL;
    AVAsset *movieAsset = [AVURLAsset URLAssetWithURL:contentURL options:nil];
    self.playerItem = [AVPlayerItem playerItemWithAsset:movieAsset];
    _videoPlayer.player = [AVPlayer playerWithPlayerItem:self.playerItem];
    //监听播放失败状态
    [self.playerItem addObserver:self forKeyPath:VideoPlayStatus options:NSKeyValueObservingOptionNew context:nil];
}

- (void)setVideoGravity:(AVLayerVideoGravity)videoGravity
{
    _videoGravity = videoGravity;
    _videoPlayer.videoGravity = videoGravity;
}

- (void)setMuted:(BOOL)muted
{
    _muted = muted;
    _videoPlayer.player.muted = muted;
}

- (void)setVideoScalingMode:(MPMovieScalingMode)videoScalingMode
{
    _videoScalingMode = videoScalingMode;
    switch (_videoScalingMode) {
        case MPMovieScalingModeNone:
            _videoPlayer.videoGravity = AVLayerVideoGravityResizeAspect;
            break;
        case MPMovieScalingModeAspectFit:
            _videoPlayer.videoGravity = AVLayerVideoGravityResizeAspect;
            break;
        case MPMovieScalingModeAspectFill:
            _videoPlayer.videoGravity = AVLayerVideoGravityResizeAspectFill;
            break;
        case MPMovieScalingModeFill:
            _videoPlayer.videoGravity = AVLayerVideoGravityResize;
            break;
        default:
            break;
    }
}

@end