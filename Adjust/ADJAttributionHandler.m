//
//  ADJAttributionHandler.m
//  adjust
//
//  Created by Pedro Filipe on 29/10/14.
//  Copyright (c) 2014 adjust GmbH. All rights reserved.
//

#import "ADJAttributionHandler.h"
#import "ADJAdjustFactory.h"
#import "ADJUtil.h"
#import "ADJActivityHandler.h"
#import "NSString+ADJAdditions.h"
#import "ADJTimer.h"

static const char * const kInternalQueueName     = "com.adjust.AttributionQueue";

@interface ADJAttributionHandler()

@property (nonatomic) dispatch_queue_t internalQueue;
@property (nonatomic, assign) id<ADJActivityHandler> activityHandler;
@property (nonatomic, assign) id<ADJLogger> logger;
@property (nonatomic, retain) ADJTimer *askInTimer;
@property (nonatomic, retain) ADJActivityPackage * attributionPackage;
@property (nonatomic, assign) BOOL paused;
@property (nonatomic, assign) BOOL hasDelegate;

@end

static const double kRequestTimeout = 60; // 60 seconds

@implementation ADJAttributionHandler

+ (id<ADJAttributionHandler>)handlerWithActivityHandler:(id<ADJActivityHandler>)activityHandler
                                 withAttributionPackage:(ADJActivityPackage *) attributionPackage
                                            startPaused:(BOOL)startPaused
                                            hasDelegate:(BOOL)hasDelegate;
{
    return [[ADJAttributionHandler alloc] initWithActivityHandler:activityHandler
                                           withAttributionPackage:attributionPackage
                                                      startPaused:startPaused
                                                      hasDelegate:hasDelegate];
}

- (id)initWithActivityHandler:(id<ADJActivityHandler>) activityHandler
       withAttributionPackage:(ADJActivityPackage *) attributionPackage
                  startPaused:(BOOL)startPaused
                  hasDelegate:(BOOL)hasDelegate;
{
    self = [super init];
    if (self == nil) return nil;

    self.internalQueue = dispatch_queue_create(kInternalQueueName, DISPATCH_QUEUE_SERIAL);
    self.activityHandler = activityHandler;
    self.logger = ADJAdjustFactory.logger;
    self.attributionPackage = attributionPackage;
    self.paused = startPaused;
    self.hasDelegate = hasDelegate;
    self.askInTimer = [ADJTimer timerWithBlock:^{ [self getAttributionInternal]; }
                                         queue:self.internalQueue];

    return self;
}

- (void) checkAttribution:(NSDictionary *)jsonDict {
    dispatch_async(self.internalQueue, ^{
        [self checkAttributionInternal:jsonDict];
    });
}

- (void) getAttributionWithDelay:(int)milliSecondsDelay {
    NSTimeInterval secondsDelay = milliSecondsDelay / 1000;
    NSTimeInterval nextAskIn = [self.askInTimer fireIn];
    if (nextAskIn > secondsDelay) {
        return;
    }

    if (milliSecondsDelay > 0) {
        [self.logger debug:@"Waiting to query attribution in %d milliseconds", milliSecondsDelay];
    }

    // cancel if any previous timers were running
    [self.askInTimer cancel];
    // set the new time the timer will fire in
    [self.askInTimer setStartTime:secondsDelay];
    // start the timer
    [self.askInTimer resume];
}

- (void) getAttribution {
    [self getAttributionWithDelay:0];
}

- (void) pauseSending {
    self.paused = YES;
}

- (void) resumeSending {
    self.paused = NO;
}

#pragma mark - internal
-(void) checkAttributionInternal:(NSDictionary *)jsonDict {
    if (jsonDict == nil || jsonDict == (id)[NSNull null]) return;

    NSDictionary* jsonAttribution = [jsonDict objectForKey:@"attribution"];
    ADJAttribution *attribution = [ADJAttribution dataWithJsonDict:jsonAttribution];

    NSNumber *timerMilliseconds = [jsonDict objectForKey:@"ask_in"];

    if (timerMilliseconds == nil) {
        BOOL updated = [self.activityHandler updateAttribution:attribution];

        if (updated) {
            [self.activityHandler launchAttributionDelegate];
        }

        [self.activityHandler setAskingAttribution:NO];

        return;
    };

    [self.activityHandler setAskingAttribution:YES];

    [self getAttributionWithDelay:[timerMilliseconds intValue]];
}

-(void) getAttributionInternal {
    if (!self.hasDelegate) {
        return;
    }
    if (self.paused) {
        [self.logger debug:@"Attribution handler is paused"];
        return;
    }
    [self.logger verbose:@"%@", self.attributionPackage.extendedString];
    if (self.askInTimer != nil) {
        [self.askInTimer cancel];
        self.askInTimer = nil;
    }

    NSMutableURLRequest *request = [self request];
    NSError *requestError;
    NSURLResponse *urlResponse = nil;

    NSData *responseData = [NSURLConnection sendSynchronousRequest:request
                                             returningResponse:&urlResponse
                                                         error:&requestError];
    // connection error
    if (requestError != nil) {
        [self.logger error:@"Failed to get attribution. (%@)", requestError.localizedDescription];
        return;
    }
    if (responseData == nil) {
        [self.logger error:@"Failed to get attribution. (empty error)"];
        return;
    }

    NSString *responseString = [[[NSString alloc] initWithData:responseData encoding:NSUTF8StringEncoding] adjTrim];
    NSInteger statusCode = ((NSHTTPURLResponse*)urlResponse).statusCode;
    [self.logger verbose:@"status code %d for attribution response: %@", statusCode, responseString];

    NSDictionary *jsonDict = [ADJUtil buildJsonDict:responseData];

    if (jsonDict == nil || jsonDict == (id)[NSNull null]) {
        [self.logger error:@"Failed to parse json attribution response: %@", responseString];
        return;
    }

    NSString* messageResponse = [jsonDict objectForKey:@"message"];

    if (messageResponse == nil) {
        messageResponse = @"No message found";
    }

    if (statusCode == 200) {
        [self.logger debug:@"%@", messageResponse];
    } else {
        [self.logger error:@"%@", messageResponse];
    }

    [self checkAttributionInternal:jsonDict];
}

#pragma mark - private

- (NSMutableURLRequest *)request {
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[self url]];
    request.timeoutInterval = kRequestTimeout;
    request.HTTPMethod = @"GET";

    [request setValue:self.attributionPackage.clientSdk forHTTPHeaderField:@"Client-Sdk"];

    return request;
}

- (NSURL *)url {
    NSString *parameters = [ADJUtil queryString:self.attributionPackage.parameters];
    NSString *relativePath = [NSString stringWithFormat:@"%@?%@", self.attributionPackage.path, parameters];
    NSURL *baseUrl = [NSURL URLWithString:ADJUtil.baseUrl];
    NSURL *url = [NSURL URLWithString:relativePath relativeToURL:baseUrl];
    
    return url;
}

@end
