//
//  CouchbaseLite.m
//  CouchbaseLite
//
//  Created by James Nocentini on 02/12/2015.
//  Copyright © 2015 Couchbase. All rights reserved.
//

#import "ReactCBLite.h"

#import "RCTLog.h"

#import "CouchbaseLite/CouchbaseLite.h"
#import "CouchbaseLiteListener/CouchbaseLiteListener.h"
#import "CBLRegisterJSViewCompiler.h"
#import <AssetsLibrary/AssetsLibrary.h>
#import "ReactCBLiteRequestHandler.h"

@implementation ReactCBLite

RCT_EXPORT_MODULE()

- (NSArray<NSString *> *)supportedEvents {
    return @[@"replicationChanged"];
}

RCT_EXPORT_METHOD(init:(RCTResponseSenderBlock)callback)
{
    NSString* username = [NSString stringWithFormat:@"u%d", arc4random() % 100000000];
    NSString* password = [NSString stringWithFormat:@"p%d", arc4random() % 100000000];
    [self initWithAuth:username password:password callback:callback];
}

RCT_EXPORT_METHOD(resumeContinuousReplications:(NSString*)databaseName){
    CBLDatabase* database = [manager databaseNamed:databaseName error:NULL];

    for(CBLReplication* repl in [database allReplications]) {
        if(repl.continuous && repl.suspended) {
            NSLog(@"resuming => %@", repl);
            repl.suspended = NO;
        }
    }
}

RCT_EXPORT_METHOD(suspendContinuousReplications:(NSString*)databaseName){
    CBLDatabase* database = [manager databaseNamed:databaseName error:NULL];

    for(CBLReplication* repl in [database allReplications]) {
        if(repl.continuous && !repl.suspended) {
            NSLog(@"suspending => %@", repl);
            repl.suspended = YES;
        }
    }
}

RCT_EXPORT_METHOD(stopContinuousReplication:(NSString*)databaseName pushOrPull:(NSString*)type) {

    CBLDatabase* database = [manager databaseNamed:databaseName error:NULL];

    for(CBLReplication* repl in [database allReplications]) {
        if(repl.continuous && !repl.pull && [type isEqualToString:@"push"]) {
            NSLog(@"Stopping %@ replication: %@", type, repl);
            [repl stop];
        }

        if(repl.continuous && repl.pull && [type isEqualToString:@"pull"]) {
            NSLog(@"Stopping %@ replication: %@", type, repl);
            [repl stop];
        }
    }
}

RCT_EXPORT_METHOD(startContinuousReplication:(NSString*)databaseName url:(NSString*)url pushOrPull:(NSString*)type cookieName:(NSString*) cookieName sessionID:(NSString*)sessionID sessionExpiryDate:(NSString*) sessionExpiryDate sessionPath:(NSString*) path callback:(RCTResponseSenderBlock)callback){
    CBLDatabase* database = [manager databaseNamed:databaseName error:NULL];

    for(CBLReplication* repl in [database allReplications]) {

        if(repl.continuous && !repl.pull && [type isEqualToString:@"push"] && repl.status != kCBLReplicationOffline) {
            NSLog(@"continuous replication task already exists => %@", repl);
            return;
        }

        if(repl.continuous && repl.pull && [type isEqualToString:@"pull"] && repl.status != kCBLReplicationOffline) {
            NSLog(@"continuous replication task already exists => %@", repl);
            return;
        }
    }

    CBLReplication *repl;

    NSURL* syncGatewayURL = [NSURL URLWithString:url];

    if([type isEqualToString:@"push"]) {
        repl = [database createPushReplication: syncGatewayURL];
    } else if([type isEqualToString:@"pull"]) {
        repl = [database createPullReplication: syncGatewayURL];
    } else {
        callback(@[[NSNull null], @"type must be 'push' or 'pull'"]);
        return;
    }

    NSDateFormatter* dateFormatter = [[NSDateFormatter alloc] init];
    dateFormatter.dateFormat = @"yyyy-MM-dd'T'HH:mm:ss.SSSZ";
    NSDate* date = [dateFormatter dateFromString:sessionExpiryDate];

    [repl setCookieNamed:cookieName withValue:sessionID path:path expirationDate:date secure:NO];

    repl.continuous = YES;

    [[NSNotificationCenter defaultCenter] addObserverForName:kCBLReplicationChangeNotification object:repl queue:nil usingBlock:^(NSNotification *notification) {

        NSString *status;
        if (repl.status == kCBLReplicationActive) {
            NSLog(@"Repication in progress");
            status = @"in-progrss";
        } else if (repl.status == kCBLReplicationOffline) {
            NSLog(@"Sync in offline");
            status = @"offline";
        } else if (repl.status == kCBLReplicationStopped) {
            NSLog(@"Sync in stopped");
            status = @"in-stopped";
        } else if (repl.status == kCBLReplicationIdle) {
            NSLog(@"Sync in idle");
            status = @"in-idle";
        }

        NSError *error = repl.lastError;
        if(error) {
            status = @"error";
            NSLog(@"replication error %@", error.code);
        }

        NSDictionary *dictionary = @{
                                     @"type": type,
                                     @"changesCount": @(repl.changesCount),
                                     @"completedChangesCount": @(repl.completedChangesCount),
                                     @"running": @(repl.running),
                                     @"status": status,
                                     @"suspended": @(repl.suspended),
                                     };

        [self sendEventWithName:@"replicationChanged" body:dictionary];

    }];

    [repl start];

    callback(@[@"replication started", [NSNull null]]);
}

RCT_EXPORT_METHOD(initWithAuth:(NSString*)username password:(NSString*)password callback:(RCTResponseSenderBlock)callback)
{
    @try {
        NSLog(@"Launching Couchbase Lite...");
        // not using [CBLManager sharedInstance] because it doesn't behave well when the app is backgrounded

        NSError *error;

        NSString* oldDir = [CBLManager defaultDirectory];
        
        NSFileManager* fileManager = [NSFileManager defaultManager];
        NSURL* containerURL = [fileManager containerURLForSecurityApplicationGroupIdentifier:@"group.com.pomocorp.pomochat"];

        NSString *dir = [[containerURL path] stringByAppendingPathComponent: @"CouchbaseLite"];
        NSLog(@"cbl dir: %@", dir);
        [fileManager createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:@{NSFileProtectionKey: NSFileProtectionCompleteUntilFirstUserAuthentication} error:&error];
        
        NSArray *files = [fileManager contentsOfDirectoryAtPath:oldDir error:&error];
        NSError *fileMoveError;
        for (NSString *file in files) {
            NSString *sourcePath = [oldDir stringByAppendingPathComponent:file];
            NSString *targetPath = [dir stringByAppendingPathComponent:file];
            [fileManager moveItemAtPath:sourcePath
                        toPath:targetPath
                         error:&fileMoveError];
            
            if(fileMoveError) {
                NSLog(@"error movng file %@, %@", file, [fileMoveError description]);
            }
        }
        
        CBLManagerOptions options = {
            NO, //readonly
            NSDataWritingFileProtectionCompleteUntilFirstUserAuthentication//fileProtection
        };
        manager = [[CBLManager alloc] initWithDirectory: dir options: &options error: &error];

        CBLRegisterJSViewCompiler();

        //register the server with CBL_URLProtocol
        [manager internalURL];

        int suggestedPort = 5984;

        listener = [self createListener:suggestedPort withUsername:username withPassword:password withCBLManager: manager];

        NSLog(@"Couchbase Lite listening on port <%@>", listener.URL.port);
        NSString *extenalUrl = [NSString stringWithFormat:@"http://%@:%@@localhost:%@/", username, password, listener.URL.port];
        callback(@[extenalUrl, [NSNull null]]);
    } @catch (NSException *e) {
        NSLog(@"Failed to start Couchbase lite: %@", e);
        callback(@[[NSNull null], e.reason]);
    }
}

- (CBLListener*) createListener: (int) port
                   withUsername: (NSString *) username
                   withPassword: (NSString *) password
                 withCBLManager: (CBLManager*) cblManager
{

    CBLListener* listener = [[CBLListener alloc] initWithManager:cblManager port:port];
    [listener setPasswords:@{username: password}];

    NSLog(@"Trying port %d", port);

    NSError *err = nil;
    BOOL success = [listener start: &err];

    if (success) {
        NSLog(@"Couchbase Lite running on %@", listener.URL);
        return listener;
    } else {
        NSLog(@"Could not start listener on port %d: %@", port, err);

        port++;

        return [self createListener:port withUsername:username withPassword:password withCBLManager: cblManager];
    }
}

RCT_EXPORT_METHOD(logLevel: (NSString*) level) {
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
}

// stop and start are needed because the OS appears to kill the listener when the app becomes inactive (when the screen is locked, or its put in the background)
RCT_EXPORT_METHOD(startListener)
{
    NSLog(@"Starting Couchbase Lite listener process");
    NSError* error;
    if ([listener start:&error]) {
        NSLog(@"Couchbase Lite listening at %@", listener.URL);
    } else {
        NSLog(@"Couchbase Lite couldn't start listener at %@: %@", listener.URL, error.localizedDescription);
    }
}

RCT_EXPORT_METHOD(stopListener)
{
    NSLog(@"Stopping Couchbase Lite listener process");
    [listener stop];
}

RCT_EXPORT_METHOD(upload:(NSString *)method
                  authHeader:(NSString *)authHeader
                  sourceUri:(NSString *)sourceUri
                  targetUri:(NSString *)targetUri
                  contentType:(NSString *)contentType
                  callback:(RCTResponseSenderBlock)callback)
{
    
    if([sourceUri hasPrefix:@"assets-library"]){
        NSLog(@"Uploading attachment from asset %@ to %@", sourceUri, targetUri);
        
        // thanks to
        // * https://github.com/kamilkp/react-native-file-transfer/blob/master/RCTFileTransfer.m
        // * http://stackoverflow.com/questions/26057394/how-to-convert-from-alassets-to-nsdata
        
        ALAssetsLibrary *library = [[ALAssetsLibrary alloc] init];
        
        [library assetForURL:[NSURL URLWithString:sourceUri] resultBlock:^(ALAsset *asset) {
            
            ALAssetRepresentation *rep = [asset defaultRepresentation];
            
            Byte *buffer = (Byte*)malloc(rep.size);
            NSUInteger buffered = [rep getBytes:buffer fromOffset:0.0 length:rep.size error:nil];
            NSData *data = [NSData dataWithBytesNoCopy:buffer length:buffered freeWhenDone:YES];
            
            [self sendData:method authHeader:authHeader data:data targetUri:targetUri contentType:contentType callback:callback];
        } failureBlock:^(NSError *error) {
            NSLog(@"Error: %@",[error localizedDescription]);
            NSMutableDictionary* returnStuff = [NSMutableDictionary dictionary];
            [returnStuff setObject: [error localizedDescription] forKey:@"error"];
            callback(@[returnStuff, [NSNull null]]);
        }];
    } else if ([sourceUri isAbsolutePath]) {
        NSLog(@"Uploading attachment from file %@ to %@", sourceUri, targetUri);
        NSData *data = [NSData dataWithContentsOfFile:sourceUri];
        [self sendData:method authHeader:authHeader data:data targetUri:targetUri contentType:contentType callback:callback];
    } else {
        NSLog(@"Uploading attachment from uri %@ to %@", sourceUri, targetUri);
        NSData *data = [NSData dataWithContentsOfURL:[NSURL URLWithString:sourceUri]];
        [self sendData:method authHeader:authHeader data:data targetUri:targetUri contentType:contentType callback:callback];
    }
}

- (void) sendData:(NSString *)method
       authHeader:(NSString *)authHeader
             data:(NSData *)data
        targetUri:(NSString *)targetUri
      contentType:(NSString *)contentType
         callback:(RCTResponseSenderBlock)callback
{
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
            if ([response isKindOfClass:[NSHTTPURLResponse class]]) {
                NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse*)response;
                
                NSLog(@"HTTP Error: %ld %@", (long)httpResponse.statusCode, error);
                
                [returnStuff setObject: error forKey:@"error"];
                [returnStuff setObject: [NSNumber numberWithFloat:httpResponse.statusCode] forKey:@"statusCode"];
            } else {
                NSLog(@"Error %@", error);
                [returnStuff setObject: error forKey:@"error"];
            }
            
            callback(@[returnStuff, [NSNull null]]);
        } else {
            NSString *responeString = [[NSString alloc] initWithData:receivedData encoding:NSUTF8StringEncoding];
            NSLog(@"responeString %@", responeString);
            
            NSData *data = [responeString dataUsingEncoding:NSUTF8StringEncoding];
            id json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
            
            [returnStuff setObject: json forKey:@"resp"];
            
            if ([response isKindOfClass:[NSHTTPURLResponse class]]) {
                NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse*)response;
                NSLog(@"status code %ld", (long)httpResponse.statusCode);
                
                [returnStuff setObject: [NSNumber numberWithFloat:httpResponse.statusCode] forKey:@"statusCode"];
            }
            
            callback(@[[NSNull null], returnStuff]);
        }
    });
}

@end
