//
//  ADJTimerOnce.m
//  adjust
//
//  Created by Pedro Filipe on 03/06/15.
//  Copyright (c) 2015 adjust GmbH. All rights reserved.
//

#import "ADJTimerOnce.h"

static const uint64_t kTimerLeeway   =  1 * NSEC_PER_SEC; // 1 second

#pragma mark - private
@interface ADJTimerOnce()

@property (nonatomic) dispatch_source_t source;
@property (nonatomic, assign, readonly) dispatch_time_t start;
@property (nonatomic, retain) NSDate * fireDate;

@end

#pragma mark -
@implementation ADJTimerOnce

+ (ADJTimerOnce *)timerWithBlock:(dispatch_block_t)block
                       queue:(dispatch_queue_t)queue
{
    return [[ADJTimerOnce alloc] initBlock:block queue:queue];
}

- (id)initBlock:(dispatch_block_t)block
          queue:(dispatch_queue_t)queue
{
    self = [super init];
    if (self == nil) return nil;

    self.source = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, queue);

    dispatch_source_set_event_handler(self.source, block);

    return self;
}
- (NSTimeInterval)fireIn {
    if (self.fireDate == nil) {
        return 0;
    }
    return [self.fireDate timeIntervalSinceNow];
}

- (void)startIn:(NSTimeInterval)startIn
{
    self.fireDate = [[NSDate date] initWithTimeIntervalSinceNow:startIn];

    dispatch_source_set_timer(self.source,
                              dispatch_walltime(NULL, startIn * NSEC_PER_SEC),
                              DISPATCH_TIME_FOREVER,
                              kTimerLeeway);
}

@end
