//
//  HMRefreshControl.m
//  HMRefresh
//
//  Created by 刘凡 on 16/1/22.
//  Copyright © 2016年 itheima. All rights reserved.
//

#import "HMRefreshControl.h"
#import "HMRefreshView.h"

/// 刷新控件偏移量
#define HMRefreshControlOffset -60

/// 刷新状态枚举
/// - HMRefreshStateNormal:       默认状态或者松开手就回到默认状态
/// - HMRefreshStatePulling:      将要刷新 - 松开手就进入刷新的状态
/// - HMRefreshStateRefreshing:   正在刷新
typedef enum : NSUInteger {
    HMRefreshStateNormal,
    HMRefreshStatePulling,
    HMRefreshStateRefreshing,
} HMRefreshState;

@interface HMRefreshControl()
@property (nonatomic) HMRefreshState refreshState;
@end

@implementation HMRefreshControl {
    __weak id __target;
    SEL __action;
    
    BOOL _isRefreshing;
    UIView *_contentView;
    CGFloat _preOffsetY;
    NSIndexPath *_prePullupIndexPath;
    NSInteger _retryTimes;
}

#pragma mark - 构造函数
- (instancetype)init {
    self = [super init];
    if (self) {
        _pullupRetryTimes = 3;
        
        dispatch_async(dispatch_get_main_queue(), ^{
            [self prepareUI];
            
            [self addObserver:self forKeyPath:@"frame" options:0 context:nil];
        });
    }
    return self;
}

- (void)dealloc {
    [self removeObserver:self forKeyPath:@"frame"];
    NSLog(@"%s", __FUNCTION__);
}

- (void)layoutSubviews {
    [super layoutSubviews];
    
    CGFloat x = _contentView.bounds.size.width * 0.5;
    CGFloat y = (self.bounds.size.height - self.pulldownView.bounds.size.height * 0.5);
    self.pulldownView.center = CGPointMake(x, y);
}

#pragma mark - 父类方法及属性
- (BOOL)isRefreshing {
    return _isRefreshing || _isPullupRefresh;
}

- (void)addTarget:(id)target action:(SEL)action forControlEvents:(UIControlEvents)controlEvents {
    __target = target;
    __action = action;
}

- (void)beginRefreshing {
    NSLog(@"开始刷新");
    
    if (!_isPullupRefresh) {
        [super beginRefreshing];
        _refreshState = HMRefreshStateRefreshing;
    } else {
        self.pullupView.tipLabel.text = @"正在刷新数据...";
    }
}

- (void)endRefreshing {
    NSLog(@"结束刷新");
    [super endRefreshing];
    
    _isRefreshing = NO;
    
    if (_isPullupRefresh) {
        [self.pullupView stopAnimating];
        _isPullupRefresh = NO;
        
        dispatch_async(dispatch_get_main_queue(), ^{
            if ([[self lastIndexPath] compare:_prePullupIndexPath] == NSOrderedSame) {
                _retryTimes++;
                self.pullupView.tipLabel.text = @"没有新数据";
            } else {
                _retryTimes = 0;
            }
            [self setPullupViewLocation];
        });
        return;
    }
    
    dispatch_async(dispatch_get_main_queue(), ^{
        [self setPullupViewLocation];
    });
    
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.3 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [self.pulldownView.refreshIndicator stopAnimating];
        self.pulldownView.pulldownIcon.hidden = NO;
        
        self.pulldownView.pulldownIcon.transform = CGAffineTransformIdentity;
        self.pulldownView.tipLabel.text = @"下拉刷新数据";
        
        _refreshState = HMRefreshStateNormal;
    });
}

#pragma mark - KVO 相关方法
- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary<NSString *,id> *)change context:(void *)context {
    
    if (self.isRefreshing) {
        return;
    }
    
    UIScrollView *scrollView = [self scrollView];
    if (scrollView == nil) {
        return;
    }
    
    if (scrollView.contentOffset.y + scrollView.contentInset.top > 0) {
        if (_preOffsetY < scrollView.contentOffset.y) {
            [self checkPullup];
        }
        _preOffsetY = scrollView.contentOffset.y;
        return;
    }
    
    if (scrollView.isDragging) {
        if (self.refreshState == HMRefreshStateNormal && self.frame.origin.y < HMRefreshControlOffset) {
            self.refreshState = HMRefreshStatePulling;
        } else if (self.refreshState == HMRefreshStatePulling && self.frame.origin.y > HMRefreshControlOffset) {
            self.refreshState = HMRefreshStateNormal;
        }
    } else {
        if (self.refreshState == HMRefreshStatePulling) {
            self.refreshState = HMRefreshStateRefreshing;
        }
    }
}

- (UIScrollView *)scrollView {
    if (![self.superview isKindOfClass:[UIScrollView class]]) {
        return nil;
    }
    
    return (UIScrollView *)self.superview;
}

/// 检查上拉刷新
- (void)checkPullup {
    
    // TODO: - 暂时仅处理 tableView
    if (![self.scrollView isKindOfClass:[UITableView class]]) {
        return;
    }
    
    if (_retryTimes == self.pullupRetryTimes) {
        return;
    }
    
    UITableView *parentView = (UITableView *)self.scrollView;
    
    _prePullupIndexPath = [self lastIndexPath];
    if (_prePullupIndexPath == nil) {
        self.pullupView.tipLabel.text = @"没有数据，无法上拉刷新";
        return;
    }
    
    UITableViewCell *cell = [parentView cellForRowAtIndexPath:_prePullupIndexPath];
    
    if (cell == nil) {
        return;
    }
    
    if (!self.pullupView.isAnimating) {
        _isPullupRefresh = YES;
        [self.pullupView startAnimating];
        
        [self sendAction:__action to:__target forEvent:[[UIEvent alloc] init]];
    }
}

- (NSIndexPath *)lastIndexPath {
    
    if (![self.scrollView isKindOfClass:[UITableView class]]) {
        return nil;
    }
    
    UITableView *parentView = (UITableView *)self.scrollView;
    
    NSInteger section = [parentView numberOfSections];
    if (section <= 0) {
        return nil;
    }
    
    NSInteger row;
    do {
        row = [parentView numberOfRowsInSection:(--section)];
    } while (row <= 0 && section > 0);
    
    if (row <= 0) {
        return nil;
    }
    
    return [NSIndexPath indexPathForRow:row - 1 inSection:section];
}

- (void)setRefreshState:(HMRefreshState)refreshState {
    _refreshState = refreshState;
    
    switch (refreshState) {
        case HMRefreshStateNormal: {
            self.pulldownView.tipLabel.text = @"下拉刷新数据";
            
            [UIView animateWithDuration:0.25 animations:^{
                self.pulldownView.pulldownIcon.transform = CGAffineTransformIdentity;
            }];
        }
            break;
        case HMRefreshStatePulling: {
            self.pulldownView.tipLabel.text = @"放开开始刷新";
            
            [UIView animateWithDuration:0.25 animations:^{
                self.pulldownView.pulldownIcon.transform = CGAffineTransformMakeRotation(M_PI);
            }];
        }
            break;
        case HMRefreshStateRefreshing:
            dispatch_async(dispatch_get_main_queue(), ^{
                self.pulldownView.tipLabel.text = @"正在刷新数据...";
                
                self.pulldownView.pulldownIcon.hidden = YES;
                [self.pulldownView.refreshIndicator startAnimating];
                
                if (!_isRefreshing) {
                    _isRefreshing = YES;
                    [self sendAction:__action to:__target forEvent:[[UIEvent alloc] init]];
                }
            });
            
            break;
    }
}

#pragma mark - 设置界面
- (void)prepareUI {
    // 1. 背景颜色
    self.backgroundColor = [UIColor whiteColor];
    self.tintColor = [UIColor clearColor];
    
    if (self.subviews.count > 0) {
        [self.subviews[0] removeFromSuperview];
    }
    
    // 2. 内容视图
    _contentView = [[UIView alloc] init];
    _contentView.clipsToBounds = YES;
    [self addSubview:_contentView];
    
    _contentView.translatesAutoresizingMaskIntoConstraints = false;
    NSDictionary *viewDict = NSDictionaryOfVariableBindings(_contentView);
    [self addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"H:|-0-[_contentView]-0-|"
                                                                 options:0
                                                                 metrics:nil
                                                                   views:viewDict]];
    [self addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"V:|-0-[_contentView]-0-|"
                                                                 options:0
                                                                 metrics:nil
                                                                   views:viewDict]];
    
    // 3. 下拉刷新视图
    if (self.pulldownView == nil) {
        self.pulldownView = [[HMRefreshView alloc] init];
    }
    [_contentView addSubview:self.pulldownView];
    
    // 4. 上拉刷新视图
    // 1> 父视图
    UIScrollView *scrollView = [self scrollView];
    if (scrollView == nil) {
        return;
    }
    
    // 2> 添加刷新视图
    if (self.pullupView == nil) {
        self.pullupView = [[HMRefreshView alloc] init];
        self.pullupView.backgroundColor = [UIColor greenColor];
    }
    [scrollView addSubview:self.pullupView];
    
    // 3> 调整底部间距
    UIEdgeInsets inset = scrollView.contentInset;
    inset.bottom += self.pullupView.bounds.size.height;
    scrollView.contentInset = inset;
    
    [self setPullupViewLocation];
}

/// 设置上拉视图位置
- (void)setPullupViewLocation {
    
    UIScrollView *scrollView = [self scrollView];
    if (scrollView == nil) {
        return;
    }
    
    CGRect rect = self.pullupView.bounds;
    
    if (scrollView.contentSize.height < scrollView.bounds.size.height) {
        scrollView.contentSize = scrollView.bounds.size;
    }
    
    rect.origin.y = scrollView.contentSize.height;
    rect.origin.x = (scrollView.bounds.size.width - rect.size.width) * 0.5;
    
    self.pullupView.frame = rect;
    self.pullupView.backgroundColor = [UIColor greenColor];
}

@end
