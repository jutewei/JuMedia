//
//  JuAVPlayer.m
//  JuMedia
//
//  Created by Juvid on 2018/3/28.
//  Copyright © 2018年 Juvid. All rights reserved.
//

#import "JuAVPlayer.h"
#import <AVFoundation/AVFoundation.h>

@interface JuAVPlayer ()
/** 播放器 */
@property (nonatomic, strong) AVPlayer *ju_player;
/** 视频资源 */
@property (nonatomic, strong) AVPlayerItem *ju_currentItem;
/** 播放器观察者 */
@property (nonatomic ,strong)  id ju_TimeObser;
// 拖动进度条的时候停止刷新数据
@property (nonatomic ,assign) BOOL isSeeking;
// 是否需要缓冲
@property (nonatomic, assign) BOOL isCanPlay;
// 是否需要缓冲
@property (nonatomic, assign) BOOL ju_needBuffer;

@end

@implementation JuAVPlayer


- (instancetype)initWithFrame:(CGRect)frame
{
    self = [super initWithFrame:frame];
    if (self) {
        [self juSetting];
    }
    return self;
}
-(void)awakeFromNib{
    [super awakeFromNib];
    [self juSetting];
}
/**
 创建播放器 AVPlayerViewController
 AVPlayerViewController的videoGravity属性设置
 AVLayerVideoGravityResize,       // 非均匀模式。两个维度完全填充至整个视图区域
 AVLayerVideoGravityResizeAspect,  // 等比例填充，直到一个维度到达区域边界
 AVLayerVideoGravityResizeAspectFill, // 等比例填充，直到填充满整个视图区域，其中一个维度的部分区域会被裁剪
 */
- (void)creatPlayerLayer{
    AVPlayerViewController  *_playerVc = [[AVPlayerViewController alloc] init];
    _playerVc.player=self.ju_player;
    _playerVc.videoGravity = AVLayerVideoGravityResize;
    _playerVc.view.translatesAutoresizingMaskIntoConstraints = YES;
    _playerVc.view.frame = self.bounds;
    [self addSubview:_playerVc.view];

}
-(void)juSetting{

    self.backgroundColor = [UIColor lightGrayColor];
    self.isCanPlay = NO;
    self.ju_needBuffer = NO;
    self.isSeeking = NO;
    /**
     * 这里view用来做AVPlayer的容器
     * 完成对AVPlayer的二次封装
     * 要求 :
     * 1. 暴露视频输出的API  视频时长 当前播放时间 进度
     * 2. 暴露出易于控制的data入口  播放 暂停 进度拖动 音量 亮度 清晰度调节
     */
}

#pragma mark - 属性和方法
- (NSTimeInterval)ju_TotalTime{
    return CMTimeGetSeconds(self.ju_player.currentItem.duration);
}

/**
 准备播放器
 @param videoURL 视频地址
 */
- (void)juSetupPlayerWith:(NSURL *)videoURL{
    [self creatPlayer:videoURL];
    [self juUseDelegateWith:JUAVPlayerStatusLoadingVideo];
}

/**
 avplayer自身有一个rate属性
 rate ==1.0，表示正在播放；rate == 0.0，暂停；rate == -1.0，播放失败
 */

/** 播放 */
- (void)juPlay{
    if (self.ju_player.rate == 0) {
        [self.ju_player play];
    }
}

/** 暂停 */
- (void)juPause{
    if (self.ju_player.rate == 1.0) {
        [self.ju_player pause];
    }
}

/** 播放|暂停 */
- (void)juPlayOrPause:(void (^)(BOOL isPlay))block;{
    if (self.ju_player.rate == 0) {
        [self.ju_player play];
        block(YES);
    }else if (self.ju_player.rate == 1.0) {
        [self.ju_player pause];
        block(NO);

    }else {
        NSLog(@"播放器出错");
    }
}

/** 拖动视频进度 */
- (void)juSeekPlayerTimeTo:(NSTimeInterval)time{
    [self juPause];
    [self juStartToSeek];
    __weak typeof(self)weakSelf = self;

    [self.ju_player seekToTime:CMTimeMake(time, 1.0) completionHandler:^(BOOL finished) {
        [weakSelf endSeek];
        [weakSelf juPlay];
    }];

}

/** 跳动中不监听 */
- (void)juStartToSeek{
    self.isSeeking = YES;
}
- (void)endSeek{
    self.isSeeking = NO;
}

/**
 切换视频

 @param videoURL 视频地址
 */
- (void)juReplacePalyerItem:(NSURL *)videoURL{
    self.isCanPlay = NO;

    [self juPause];
    [self removeNotification];
    [self removeObserverWithPlayItem:self.ju_currentItem];

    self.ju_currentItem = [self juGetPlayerItem:videoURL];
    [self.ju_player replaceCurrentItemWithPlayerItem:self.ju_currentItem];
    [self addObserverWithPlayItem:self.ju_currentItem];
    [self addNotificatonForPlayer];

    [self juPlay];

}


/**
 播放状态代理调用

 @param status 播放状态
 */
- (void)juUseDelegateWith:(JUAVPlayerStatus)status{

    if (self.isCanPlay == NO) {
        return;
    }

    if (self.ju_Delegate && [self.ju_Delegate respondsToSelector:@selector(juPromptPlayerStatusOrErrorWith:)]) {
        [self.ju_Delegate juPromptPlayerStatusOrErrorWith:status];
    }
}


#pragma mark - 创建播放器
/**
 获取播放item

 @param videoURL 视频网址

 @return AVPlayerItem
 */
- (AVPlayerItem *)juGetPlayerItem:(NSURL *)videoURL{
    AVPlayerItem *item = [AVPlayerItem playerItemWithURL:videoURL];
    return item;
}
/**
 创建播放器
 */
- (void)creatPlayer:(NSURL *)videoURL{
    if (!_ju_player) {

        self.ju_currentItem = [self juGetPlayerItem:videoURL];

        _ju_player = [AVPlayer playerWithPlayerItem:self.ju_currentItem];

        [self creatPlayerLayer];

        [self addPlayerObserver];

        [self addObserverWithPlayItem:self.ju_currentItem];

        [self addNotificatonForPlayer];
    }
}



#pragma mark - 添加 监控
/** 给player 添加 time observer */
- (void)addPlayerObserver{
    __weak typeof(self)weakSelf = self;
    _ju_TimeObser = [self.ju_player addPeriodicTimeObserverForInterval:CMTimeMake(1.0, 1.0) queue:dispatch_get_main_queue() usingBlock:^(CMTime time) {
        AVPlayerItem *playerItem = weakSelf.ju_player.currentItem;

        float current = CMTimeGetSeconds(time);

        float total = CMTimeGetSeconds([playerItem duration]);

        if (weakSelf.isSeeking) {
            return;
        }

        if (weakSelf.ju_Delegate && [weakSelf.ju_Delegate respondsToSelector:@selector(juPlayProgress:currentTime:LoadRange:)]) {
            [weakSelf.ju_Delegate juPlayProgress:total currentTime:current LoadRange:weakSelf.ju_LoadRange];
        }
    }];
}
/** 移除 time observer */
- (void)removePlayerObserver{
    [_ju_player removeTimeObserver:_ju_TimeObser];
}

/** 给当前播放的item 添加观察者

 需要监听的字段和状态
 status :  AVPlayerItemStatusUnknown,AVPlayerItemStatusReadyToPlay,AVPlayerItemStatusFailed
 loadedTimeRanges  :  缓冲进度
 playbackBufferEmpty : seekToTime后，缓冲数据为空，而且有效时间内数据无法补充，播放失败
 playbackLikelyToKeepUp : seekToTime后,可以正常播放，相当于readyToPlay，一般拖动滑竿菊花转，到了这个这个状态菊花隐藏

 */
- (void)addObserverWithPlayItem:(AVPlayerItem *)item{
    [item addObserver:self forKeyPath:@"status" options:NSKeyValueObservingOptionNew context:nil];
    [item addObserver:self forKeyPath:@"loadedTimeRanges" options:NSKeyValueObservingOptionNew context:nil];
    [item addObserver:self forKeyPath:@"playbackBufferEmpty" options:NSKeyValueObservingOptionNew context:nil];
    [item addObserver:self forKeyPath:@"playbackLikelyToKeepUp" options:NSKeyValueObservingOptionNew context:nil];
}
/** 移除 item 的 observer */
- (void)removeObserverWithPlayItem:(AVPlayerItem *)item{
    [item removeObserver:self forKeyPath:@"status"];
    [item removeObserver:self forKeyPath:@"loadedTimeRanges"];
    [item removeObserver:self forKeyPath:@"playbackBufferEmpty"];
    [item removeObserver:self forKeyPath:@"playbackLikelyToKeepUp"];
}
/** 数据处理 获取到观察到的数据 并进行处理 */
- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary<NSKeyValueChangeKey,id> *)change context:(void *)context{
    AVPlayerItem *item = object;
    if ([keyPath isEqualToString:@"status"]) {// 播放状态

        [self handleStatusWithPlayerItem:item];

    } else if ([keyPath isEqualToString:@"loadedTimeRanges"]) {// 缓冲进度

        [self handleLoadedTimeRangesWithPlayerItem:item];

    } else if ([keyPath isEqualToString:@"playbackBufferEmpty"]) {// 跳转后没数据

        if (self.isCanPlay) {
            NSLog(@"跳转后没数据");
            self.ju_needBuffer = YES;
            [self juUseDelegateWith:JUAVPlayerStatusCacheData];
        }
    } else if ([keyPath isEqualToString:@"playbackLikelyToKeepUp"]) {// 跳转后有数据
        if (self.isCanPlay && self.ju_needBuffer) {

            NSLog(@"跳转后有数据");

            self.ju_needBuffer = NO;

            [self juUseDelegateWith:JUAVPlayerStatusCacheEnd];
        }

    }
}
/**
 处理 AVPlayerItem 播放状态
 AVPlayerItemStatusUnknown           状态未知
 AVPlayerItemStatusReadyToPlay       准备好播放
 AVPlayerItemStatusFailed            播放出错
 */
- (void)handleStatusWithPlayerItem:(AVPlayerItem *)item
{
    AVPlayerItemStatus status = item.status;
    switch (status) {
        case AVPlayerItemStatusReadyToPlay:   // 准备好播放
            self.isCanPlay = YES;
            [self juUseDelegateWith:JUAVPlayerStatusReadyToPlay];
            break;
        case AVPlayerItemStatusFailed:        // 播放出错
            [self juUseDelegateWith:JUAVPlayerStatusItemFailed];
            break;
        case AVPlayerItemStatusUnknown:       // 状态未知
            break;

        default:
            break;
    }

}
/** 处理缓冲进度 */
- (void)handleLoadedTimeRangesWithPlayerItem:(AVPlayerItem *)item{
    NSArray *loadArray = item.loadedTimeRanges;

    CMTimeRange range = [[loadArray firstObject] CMTimeRangeValue];

    float start = CMTimeGetSeconds(range.start);

    float duration = CMTimeGetSeconds(range.duration);

    NSTimeInterval totalTime = start + duration;// 缓存总长度

    _ju_LoadRange = totalTime;
    //    NSLog(@"缓冲进度 -- %.2f",totalTime);

}


/**
 添加关键通知

 AVPlayerItemDidPlayToEndTimeNotification     视频播放结束通知
 AVPlayerItemTimeJumpedNotification           视频进行跳转通知
 AVPlayerItemPlaybackStalledNotification      视频异常中断通知
 UIApplicationDidEnterBackgroundNotification  进入后台
 UIApplicationDidBecomeActiveNotification     返回前台

 */
- (void)addNotificatonForPlayer{

    NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
    [center addObserver:self selector:@selector(videoPlayEnd:) name:AVPlayerItemDidPlayToEndTimeNotification object:nil];
    [center addObserver:self selector:@selector(videoPlayError:) name:AVPlayerItemPlaybackStalledNotification object:nil];
    [center addObserver:self selector:@selector(videoPlayEnterBack:) name:UIApplicationDidEnterBackgroundNotification object:nil];
    [center addObserver:self selector:@selector(videoPlayBecomeActive:) name:UIApplicationDidBecomeActiveNotification object:nil];
}
/** 移除 通知 */
- (void)removeNotification{
    NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
    [center removeObserver:self name:AVPlayerItemDidPlayToEndTimeNotification object:nil];
    [center removeObserver:self name:AVPlayerItemPlaybackStalledNotification object:nil];
    [center removeObserver:self name:UIApplicationDidEnterBackgroundNotification object:nil];
    [center removeObserver:self name:UIApplicationDidBecomeActiveNotification object:nil];
    [center removeObserver:self];
}

/** 视频播放结束 */
- (void)videoPlayEnd:(NSNotification *)notic{
    NSLog(@"视频播放结束");
    [self juUseDelegateWith:JUAVPlayerStatusPlayEnd];
    [self.ju_player seekToTime:kCMTimeZero];
}
///** 视频进行跳转 */ 没有意义的方法 会被莫名的多次调动，不清楚机制
//- (void)videoPlayToJump:(NSNotification *)notic
//{
//    NSLog(@"视频进行跳转");
//}
/** 视频异常中断 */
- (void)videoPlayError:(NSNotification *)notic{
    NSLog(@"视频中断");
    [self juUseDelegateWith:JUAVPlayerStatusPlayStop];
}
/** 进入后台 */
- (void)videoPlayEnterBack:(NSNotification *)notic{
    NSLog(@"进入后台");
    [self juUseDelegateWith:JUAVPlayerStatusEnterBack];
}
/** 返回前台 */
- (void)videoPlayBecomeActive:(NSNotification *)notic{
    NSLog(@"返回前台");
    [self juUseDelegateWith:JUAVPlayerStatusBecomeActive];
}

#pragma mark - 销毁 release
- (void)dealloc{
    [self removeNotification];
    [self removePlayerObserver];
    [self removeObserverWithPlayItem:self.ju_player.currentItem];
}

@end
