//
//  ScreenDetails.m
//  CrashOps
//
//  Created by CrashOps on 20/04/2020.
//  Copyright © 2020 CrashOps. All rights reserved.
//

#import "ScreenDetails.h"
#import "ViewDetails.h"
#import "CrashOpsController.h"

@interface ScreenDetails()

@property (nonatomic, strong) NSString *className;
@property (nonatomic, strong) ViewDetails *viewDetails;
/// Note: This timestamp is actually in milliseconds, unlike Apple's common representation (with seconds).
@property (nonatomic, assign) NSTimeInterval timestamp;

@end

@implementation ScreenDetails

- (instancetype)initWithViewController:(UIViewController *)viewController {
    self = [super init];

    if (self) {
        _className = [viewController.class description];
        _viewDetails = [[ViewDetails alloc] initWithView: viewController.view depth: 0];

        //[co_ToastMessage show: [_viewDetails description] delayInSeconds: 5 onDone: nil];

        _timestamp = _timestamp_milliseconds();
    }

    return self;
}

- (NSString *)description {
    return [NSString stringWithFormat:@"{'className': %@, 'view hierarchy': %@}", _className, _viewDetails.description];
}

- (NSDictionary *)toDictionary {
    return [ScreenDetails _toDictionary: self];
}

+(NSDictionary *) _toDictionary:(ScreenDetails *) screenDetails {
    NSMutableDictionary *screenDetailsDictionary = [NSMutableDictionary new];
    [screenDetailsDictionary setObject: [screenDetails className] forKey: @"name"];
    [screenDetailsDictionary setObject: [NSNumber numberWithInteger: (NSInteger)[screenDetails timestamp]] forKey: @"timestamp"];
    [screenDetailsDictionary setObject: [[screenDetails viewDetails] toDictionary] forKey: @"views"];

    return screenDetailsDictionary;
}


@end