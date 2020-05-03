//
//  ScreenTracer.m
//  CrashOps
//
//  Created by CrashOps on 20/04/2020.
//  Copyright © 2020 CrashOps. All rights reserved.
//

#import "ScreenTracer.h"
#import "ScreenDetails.h"

@interface ScreenTracer () <ViewControllerTracer>

@property (nonatomic, strong) NSMutableArray *collectedTraces;

@end

@implementation ScreenTracer

- (instancetype)init
{
    self = [super init];

    if (self) {
        _collectedTraces = [NSMutableArray new];
    }

    return self;
}

-(NSArray *) allTraces {
    return [self.collectedTraces copy];
}

- (NSArray *) breadcrumbsReport {
    return [self allTraces];
}

- (void) addViewController:(UIViewController *)viewController {
    [self.collectedTraces addObject: [[ScreenDetails alloc] initWithViewController: viewController]];
}

@end
