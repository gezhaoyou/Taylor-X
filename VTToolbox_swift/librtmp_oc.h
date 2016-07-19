//
//  librtmp_oc.h
//  VTToolbox_swift
//
//  Created by gezhaoyou on 16/7/14.
//  Copyright © 2016年 bravovcloud. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface librtmp_oc : NSObject

-(void) startRtmpSession;

-(void) srsRtmpWritePacket:(int)timestamp data:(char *) data  size:(int) size;


@end
