//
//  CouchbaseLite.h
//  CouchbaseLite
//
//  Created by James Nocentini on 02/12/2015.
//  Copyright © 2015 Couchbase. All rights reserved.
//

#import <RCTBridgeModule.h>
#import <CouchbaseLiteListener/CBLListener.h>
#import <CouchbaseLite/CouchbaseLite.h>
#import "RCTEventEmitter.h"

@interface ReactCBLite : RCTEventEmitter <RCTBridgeModule>
{
    CBLListener *listener;
    CBLManager *manager;
}
@end
