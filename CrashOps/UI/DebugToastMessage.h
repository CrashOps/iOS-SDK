//
//  DebugToastMessage.h
//  CrashOps
//
//  Created by CrashOps on 20/04/2020.
//  Copyright © 2020 CrashOps. All rights reserved.
//

#import <UIKit/UIKit.h>

typedef void(^co_ToastCallback)(void);

@interface co_ToastMessage : UIView

+(void) show:(NSString *_Nonnull) messageText delayInSeconds:(NSTimeInterval) delay onDone:(nullable void (^)(void)) callback;

@property (nonatomic, strong) UILabel * _Nonnull messageLabel;
@property (nonatomic, assign) NSTimeInterval delay;
@property (nonatomic, assign) co_ToastCallback _Nullable callback;

@end
