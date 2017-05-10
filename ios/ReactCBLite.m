//
//  CouchbaseLite.m
//  CouchbaseLite
//
//  Created by James Nocentini on 02/12/2015.
//  Copyright © 2015 Couchbase. All rights reserved.
//

#import "ReactCBLite.h"
#import <React/RCTLog.h>
#import "CouchbaseLite/CouchbaseLite.h"
#import "CouchbaseLiteListener/CouchbaseLiteListener.h"
#import "CBLRegisterJSViewCompiler.h"
#import <AssetsLibrary/AssetsLibrary.h>
#import "ReactCBLiteRequestHandler.h"

@implementation ReactCBLite

RCT_EXPORT_MODULE()

- (dispatch_queue_t)methodQueue
{
    return dispatch_get_main_queue();
}

- (NSArray<NSString *> *)supportedEvents
{
    return @[@"replicationChanged"];
}

const int DEFAULT_PORT = 5984;

RCT_EXPORT_METHOD(init:(NSDictionary*)options :(RCTPromiseResolveBlock)resolve :(RCTPromiseRejectBlock)reject)
{
    @try {
        RCTLogTrace(@"rncbl - Launching Couchbase Lite...");
        
        // not using [CBLManager sharedInstance] because it doesn't behave well when the app is backgrounded
        NSString *username = [options objectForKey:@"username"];
        NSString *password = [options objectForKey:@"password"];
        NSString *databaseDir = [options objectForKey:@"databaseDir"];
        
        if(!databaseDir) {
            databaseDir = [CBLManager defaultDirectory];
        }
        
        if(!username) {
            username = [[NSUUID UUID] UUIDString];
        }
        
        if(!password) {
            password = [[NSUUID UUID] UUIDString];
        }
        
        NSError *error;
        
        CBLManagerOptions options = {
            NO, //readonly
            NSDataWritingFileProtectionCompleteUntilFirstUserAuthentication//fileProtection
        };
        manager = [[CBLManager alloc] initWithDirectory:databaseDir options:&options error:&error];
        
        if(error) {
            return reject(@"cbl error", @"failed to start", error);
        }
        
        CBLRegisterJSViewCompiler();
        
        //register the server with CBL_URLProtocol
        [manager internalURL];
        
        listener = [ReactCBLite createListener:DEFAULT_PORT withUsername:username withPassword:password withCBLManager: manager];
        
        RCTLogTrace(@"rncbl - Couchbase Lite listening on port <%@>", listener.URL.port);
        
        resolve(@{
                  @"listenerPort": listener.URL.port,
                  @"listenerHost": listener.URL.host,
                  @"listenerUrl": [listener.URL absoluteString],
                  @"listenerUrlWithAuth": [NSString stringWithFormat:@"http://%@:%@@localhost:%@/", username, password, listener.URL.port],
                  @"iosInternalUrl": @"http://lite.couchbase./",
                  @"username": username,
                  @"password": password
                  });
    } @catch (NSException *e) {
        RCTLogError(@"rncbl - Failed to start Couchbase lite: %@", e);
        reject(@"cbl error", e.reason, nil);
    }
}

+ (CBLListener*) createListener: (int) port
                   withUsername: (NSString *) username
                   withPassword: (NSString *) password
                 withCBLManager: (CBLManager*) cblManager
{
    
    CBLListener *cblLlistener = [[CBLListener alloc] initWithManager:cblManager port:port];
    [cblLlistener setPasswords:@{username: password}];
    
    RCTLogTrace(@"rncbl - Trying port %d", port);
    
    NSError *err = nil;
    BOOL success = [cblLlistener start: &err];
    
    if (success) {
        RCTLogTrace(@"rncbl - Couchbase Lite running on %@", cblLlistener.URL);
        return cblLlistener;
    } else {
        RCTLogTrace(@"rncbl - Could not start listener on port %d: %@", port, err);
        
        port++;
        
        return [self createListener:port withUsername:username withPassword:password withCBLManager: cblManager];
    }
}

RCT_EXPORT_METHOD(logLevel: (NSString*) level :(RCTPromiseResolveBlock)resolve :(RCTPromiseRejectBlock)reject) {
    // only debug and verbose are used
    
    if([level isEqualToString:@"VERBOSE"] || [level isEqualToString:@"DEBUG"]) {
        [CBLManager enableLogging:@"ArrayDiff"];
        [CBLManager enableLogging:@"BLIP"];
        [CBLManager enableLogging:@"BLIPLifecycle"];
        [CBLManager enableLogging:@"ChangeTracker"];
        [CBLManager enableLogging:@"Listener"];
        [CBLManager enableLogging:@"Model"];
        [CBLManager enableLogging:@"MultiStreamWriter"];
        [CBLManager enableLogging:@"Reachability"];
        [CBLManager enableLogging:@"RemoteRequest"];
        [CBLManager enableLogging:@"Server"];
        [CBLManager enableLogging:@"Sync"];
        [CBLManager enableLogging:@"Upgrade"];
        [CBLManager enableLogging:@"Validation"];
        [CBLManager enableLogging:@"View"];
        [CBLManager enableLogging:@"WS"];
    }
    
    if([level isEqualToString:@"VERBOSE"]) {
        [CBLManager enableLogging:@"Database"];
        //[CBLManager enableLogging:@"JSONReader"];
        [CBLManager enableLogging:@"SQL"];
        [CBLManager enableLogging:@"Query"];
        [CBLManager enableLogging:@"Router"];
        [CBLManager enableLogging:@"SyncPerf"];
    }
    
    resolve(nil);
}

// stop and start are needed because the OS appears to kill the listener when the app becomes inactive (when the screen is locked, or its put in the background)
RCT_EXPORT_METHOD(startListener :(RCTPromiseResolveBlock)resolve :(RCTPromiseRejectBlock)reject)
{
    RCTLogTrace(@"rncbl - Starting Couchbase Lite listener process");
    NSError* error;
    if ([listener start:&error]) {
        RCTLogTrace(@"rncbl - Couchbase Lite listening at %@", listener.URL);
        resolve(nil);
    } else {
        RCTLogWarn(@"rncbl - Couchbase Lite couldn't start listener at %@: %@", listener.URL, error.localizedDescription);
        reject(@"cbl error", error.description, error);
    }
}

RCT_EXPORT_METHOD(stopListener :(RCTPromiseResolveBlock)resolve :(RCTPromiseRejectBlock)reject)
{
    RCTLogTrace(@"rncbl - Stopping Couchbase Lite listener process");
    [listener stop];
    resolve(nil);
}

RCT_EXPORT_METHOD(resumeContinuousReplications:(NSString*)databaseName :(RCTPromiseResolveBlock)resolve :(RCTPromiseRejectBlock)reject){
    CBLDatabase* database = [manager databaseNamed:databaseName error:NULL];
    
    for(CBLReplication* repl in [database allReplications]) {
        if(repl.continuous && repl.suspended) {
            RCTLogTrace(@"rncbl - resuming => %@", repl);
            repl.suspended = NO;
        }
    }
    
    resolve(nil);
}

RCT_EXPORT_METHOD(suspendContinuousReplications:(NSString*)databaseName :(RCTPromiseResolveBlock)resolve :(RCTPromiseRejectBlock)reject){
    CBLDatabase* database = [manager databaseNamed:databaseName error:NULL];
    
    for(CBLReplication* repl in [database allReplications]) {
        if(repl.continuous && !repl.suspended) {
            RCTLogTrace(@"rncbl - suspending => %@", repl);
            repl.suspended = YES;
        }
    }
    
    resolve(nil);
}

RCT_EXPORT_METHOD(stopContinuousReplication:(NSString*)databaseName pushOrPull:(NSString*)type :(RCTPromiseResolveBlock)resolve :(RCTPromiseRejectBlock)reject) {
    RCTLogTrace(@"rncbl - Stopping continuous %@ replication", type);
    
    CBLDatabase* database = [manager databaseNamed:databaseName error:NULL];
    
    for(CBLReplication* repl in [database allReplications]) {
        if(!repl.continuous)
            continue;
        
        if(!repl.pull && [type isEqualToString:@"push"]) {
            RCTLogTrace(@"rncbl - Stopping replication: %@", repl);
            [[NSNotificationCenter defaultCenter] removeObserver: self];
            [repl stop];
        } else if(repl.pull && [type isEqualToString:@"pull"]) {
            RCTLogTrace(@"rncbl - Stopping replication: %@", repl);
            [[NSNotificationCenter defaultCenter] removeObserver: self];
            [repl stop];
        } else {
            RCTLogTrace(@"rncbl - got a continuous replication that doesn't match!?: %@", repl);
        }
    }
    
    resolve(nil);
}

RCT_EXPORT_METHOD(startContinuousReplication:(NSString*)databaseName :(NSString*)url :(NSDictionary*)options :(RCTPromiseResolveBlock)resolve :(RCTPromiseRejectBlock)reject){
    CBLDatabase* database = [manager databaseNamed:databaseName error:NULL];
    
    NSString *type = [options valueForKey:@"type"];
    
    for(CBLReplication* repl in [database allReplications]) {
        
        if(repl.continuous && !repl.pull && [type isEqualToString:@"push"] && repl.status != kCBLReplicationOffline) {
            RCTLogTrace(@"rncbl - continuous replication task already exists => %@", repl);
            return resolve(nil);
        }
        
        if(repl.continuous && repl.pull && [type isEqualToString:@"pull"] && repl.status != kCBLReplicationOffline) {
            RCTLogTrace(@"rncbl - continuous replication task already exists => %@", repl);
            return resolve(nil);
        }
    }
    
    CBLReplication *repl;
    
    NSURL* syncGatewayURL = [NSURL URLWithString:url];
    
    if([type isEqualToString:@"push"]) {
        repl = [database createPushReplication: syncGatewayURL];
    } else if([type isEqualToString:@"pull"]) {
        repl = [database createPullReplication: syncGatewayURL];
    } else {
        return reject(@"cbl error", @"type must be 'push' or 'pull'", nil);
    }
    
    NSString *sessionID = [options valueForKey:@"sessionId"];
    
    NSString *cookieName = @"SyncGatewaySession";
    if([options valueForKey:@"cookieName"]) {
        cookieName = [options valueForKey:@"cookieName"];
    }
    
    NSString *path = nil;//todo: add to options
    
    NSDate *expirationDate = nil;//todo: add to options (and format)
    
    BOOL secure = NO;
    if([options valueForKey:@"secure"]) {
        secure = [[options valueForKey:@"secure"] boolValue] ? YES : NO;
    }
    
    [repl setCookieNamed:cookieName withValue:sessionID path:path expirationDate:expirationDate secure:secure];
    
    repl.continuous = YES;
    
    [[NSNotificationCenter defaultCenter] addObserver: self
                                             selector: @selector(replicationChanged:)
                                                 name: kCBLReplicationChangeNotification
                                               object: repl];
    
    [repl start];
    
    RCTLogTrace(@"rncbl - continuous %@ replication started", type);
    
    resolve(nil);
}

- (void) replicationChanged: (NSNotification*)notification {
    CBLReplication *repl = [notification object];
    NSString *type = [repl pull] ? @"pull" : @"push";
    
    NSString *status = @"unknown";
    if (repl.status == kCBLReplicationActive) {
        status = @"active";
    } else if (repl.status == kCBLReplicationOffline) {
        status = @"offline";
    } else if (repl.status == kCBLReplicationStopped) {
        status = @"stopped";
    } else if (repl.status == kCBLReplicationIdle) {
        status = @"idle";
    }
    
    NSString *lastError = @"";
    NSError *error = repl.lastError;
    if(error) {
        long lastErrorCode = (long)error.code;
        lastError = error.description;
        RCTLogInfo(@"rncbl - replication error %ld: %@", lastErrorCode, lastError);
    }
    
    NSDictionary *dictionary = @{
                                 @"type": type,
                                 @"changesCount": @(repl.changesCount),
                                 @"completedChangesCount": @(repl.completedChangesCount),
                                 @"running": @(repl.running),
                                 @"status": status,
                                 @"suspended": @(repl.suspended),
                                 @"lastError": lastError
                                 };
    
    [self sendEventWithName:@"replicationChanged" body:dictionary];
}

RCT_EXPORT_METHOD(copyAttachment:(NSString *)databaseName :(NSString *)id :(NSString *)attachmentName :(NSString *)path :(RCTPromiseResolveBlock)resolve :(RCTPromiseRejectBlock)reject) {
    CBLDatabase* database = [manager databaseNamed:databaseName error:NULL];
    CBLDocument* doc = [database documentWithID: id];
    CBLRevision* rev = doc.currentRevision;
    CBLAttachment* att = [rev attachmentNamed: attachmentName];
    if (att != nil) {
        NSData* imageData = att.content;
        [imageData writeToFile:path atomically:YES];
        return resolve(nil);
    }
    
    return reject(@"cbl error", @"cannot copy attachment", nil);
}

RCT_EXPORT_METHOD(upload:(NSString *)method
                  :(NSString *)authHeader
                  :(NSString *)sourceUri
                  :(NSString *)targetUri
                  :(NSString *)contentType
                  :(RCTPromiseResolveBlock)resolve
                  :(RCTPromiseRejectBlock)reject)
{
    
    if([sourceUri hasPrefix:@"assets-library"]){
        RCTLogTrace(@"rncbl - Uploading attachment from asset %@ to %@", sourceUri, targetUri);
        
        // thanks to
        // * https://github.com/kamilkp/react-native-file-transfer/blob/master/RCTFileTransfer.m
        // * http://stackoverflow.com/questions/26057394/how-to-convert-from-alassets-to-nsdata
        
        ALAssetsLibrary *library = [[ALAssetsLibrary alloc] init];
        
        [library assetForURL:[NSURL URLWithString:sourceUri] resultBlock:^(ALAsset *asset) {
            
            ALAssetRepresentation *rep = [asset defaultRepresentation];
            
            Byte *buffer = (Byte*)malloc(rep.size);
            NSUInteger buffered = [rep getBytes:buffer fromOffset:0.0 length:rep.size error:nil];
            NSData *data = [NSData dataWithBytesNoCopy:buffer length:buffered freeWhenDone:YES];
            
            [self sendData:method authHeader:authHeader data:data targetUri:targetUri contentType:contentType resolve:resolve reject:reject];
        } failureBlock:^(NSError *error) {
            return reject(@"cbl error", error.description, error);
        }];
    } else if ([sourceUri isAbsolutePath]) {
        RCTLogTrace(@"rncbl - Uploading attachment from file %@ to %@", sourceUri, targetUri);
        NSData *data = [NSData dataWithContentsOfFile:sourceUri];
        [self sendData:method authHeader:authHeader data:data targetUri:targetUri contentType:contentType resolve:resolve reject:reject];
    } else {
        RCTLogTrace(@"rncbl - Uploading attachment from uri %@ to %@", sourceUri, targetUri);
        NSData *data = [NSData dataWithContentsOfURL:[NSURL URLWithString:sourceUri]];
        [self sendData:method authHeader:authHeader data:data targetUri:targetUri contentType:contentType resolve:resolve reject:reject];
    }
}

- (void) sendData:(NSString *)method
       authHeader:(NSString *)authHeader
             data:(NSData *)data
        targetUri:(NSString *)targetUri
      contentType:(NSString *)contentType
          resolve:(RCTPromiseResolveBlock)resolve
           reject:(RCTPromiseRejectBlock)reject {
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:targetUri]];
    
    [request setHTTPMethod:method];
    [request setValue:contentType forHTTPHeaderField:@"Content-Type"];
    [request setValue:authHeader forHTTPHeaderField:@"Authorization"];
    [request setHTTPBody:data];
    
    NSMutableDictionary* returnStuff = [NSMutableDictionary dictionary];
    
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        
        NSURLResponse *response;
        NSError *error = nil;
        NSData *receivedData = [NSURLConnection sendSynchronousRequest:request returningResponse:&response error:&error];
        
        if (error) {
            return reject(@"cbl error", error.description, error);
        } else {
            NSString *responeString = [[NSString alloc] initWithData:receivedData encoding:NSUTF8StringEncoding];
            RCTLogTrace(@"rncbl - responeString %@", responeString);
            
            NSData *data = [responeString dataUsingEncoding:NSUTF8StringEncoding];
            id json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
            
            [returnStuff setObject: json forKey:@"resp"];
            
            if ([response isKindOfClass:[NSHTTPURLResponse class]]) {
                NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse*)response;
                RCTLogTrace(@"rncbl - status code %ld", (long)httpResponse.statusCode);
                
                [returnStuff setObject: [NSNumber numberWithFloat:httpResponse.statusCode] forKey:@"statusCode"];
            }
            
            return resolve(returnStuff);
        }
    });
}

@end
