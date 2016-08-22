#import <Foundation/Foundation.h>
#import "SyncObserver.h"

@implementation SyncObserver

- (void) replicationChanged: (NSNotification*)notification {
    NSLog(@"notiication %@", [notification name]);
    CBLReplication* repl = [self repl];

    if(repl.status == kCBLReplicationActive) {
        NSLog(@"active");
    } else if (repl.status == kCBLReplicationIdle){
        NSLog(@"idle");
    } else if (repl.status == kCBLReplicationStopped){
        NSLog(@"stopped");
        [[NSNotificationCenter defaultCenter] removeObserver: self];
        return _resolve(nil);
    } else if (repl.status == kCBLReplicationOffline){
        NSLog(@"offline");

//        NSError *error = [[NSError alloc] initWithDomain:@"couchbase.reactnativecblite"
//                                                    code:0
//                                                userInfo:@{@"Cause": @"offline"}];
//        [[NSNotificationCenter defaultCenter] removeObserver: self];
//        [repl stop];
//        return _reject(error.domain, error.localizedDescription, error);
    }
}

@end