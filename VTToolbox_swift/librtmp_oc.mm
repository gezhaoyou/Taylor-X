//
//  librtmp_oc.m
//  VTToolbox_swift
//
//  Created by gezhaoyou on 16/7/14.
//  Copyright © 2016年 bravovcloud. All rights reserved.
//

#import "librtmp_oc.h"
#include "srs_rtmp.hpp"
@implementation librtmp_oc

srs_rtmp_t rtmp;


-(void)startRtmpSession
{
    NSLog(@"hello OC\n");
    rtmp = srs_rtmp_create("rtmp://192.168.9.49/live/livedemo");
    
    if (srs_rtmp_handshake(rtmp) != 0) {
        printf("error!");
    }
    
    // create rtmp connection  <--- zhaoyou add
    if (srs_rtmp_connect_app(rtmp) != 0) {
        
    }
    srs_human_trace("connect vhost/app success");
    
    if (srs_rtmp_publish_stream(rtmp) != 0) {
        srs_human_trace("publish stream failed.");
    }
    srs_human_trace("publish stream success");
}

-(void) srsRtmpWritePacket:(int)timestamp data:(char *) data  size:(int) size
{
    char * video_data = new char[size];
//    A* pa = new A[3]
    memcpy(video_data, data, size);
    srs_rtmp_write_packet(rtmp, SRS_RTMP_TYPE_VIDEO, timestamp, video_data, size);
}

@end



