#import "RCTEventDispatcher.h"
#import <Foundation/Foundation.h>
#import "CouchbaseLite/CouchbaseLite.h"

@interface SyncObserver : NSObject

@property (nonatomic, strong) RCTPromiseResolveBlock resolve;
@property (nonatomic, strong) RCTPromiseRejectBlock reject;
@property (nonatomic, strong) CBLReplication* repl;

- (void)replicationChanged:(NSNotification*)notification;
- (void)errorCallback: (NSError*) error;

@end