//
//  AVCEncoder.swift
//  VTToolbox_swift
//
//  Created by gezhaoyou on 16/7/7.
//  Copyright © 2016年 bravovcloud. All rights reserved.
//

// import Foundation
import AVFoundation
import VideoToolbox
import CoreFoundation

final class AVCEncoder: NSObject {
    private var h264File:String!
    private var session:VTCompressionSessionRef?
    private var fileHandle:NSFileHandle!
    private var videoTimestamp:CMTime = kCMTimeZero
    private var realVideoTimeStamp:Double = 0
    
    private let srs_rtmp:librtmp_oc? = librtmp_oc()
    
    var formatDescription:CMFormatDescriptionRef? = nil {
        didSet {
            guard !CMFormatDescriptionEqual(formatDescription, oldValue) else {
                return
            }
            
            didSetFormatDescription(video: formatDescription)
        }
    }
  
    private var callback:VTCompressionOutputCallback = {(
        outputCallbackRefCon:UnsafeMutablePointer<Void>,
        sourceFrameRefCon:UnsafeMutablePointer<Void>,
        status:OSStatus,
        infoFlags:VTEncodeInfoFlags,
        sampleBuffer:CMSampleBuffer?
        ) in
        guard let sampleBuffer:CMSampleBuffer = sampleBuffer where status == noErr else {
            return
        }
        
        // print("get h.264 data!")
        let encoder:AVCEncoder = unsafeBitCast(outputCallbackRefCon, AVCEncoder.self)
        
        let isKeyframe = !CFDictionaryContainsKey(unsafeBitCast(CFArrayGetValueAtIndex(CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, true), 0), CFDictionary.self), unsafeBitCast(kCMSampleAttachmentKey_NotSync, UnsafePointer<Void>.self))
        
        if isKeyframe {
            encoder.formatDescription = CMSampleBufferGetFormatDescription(sampleBuffer)
        }
        encoder.sampleOutput(video: sampleBuffer)
    }
    
    // 264 description
    private func didSetFormatDescription(video formatDescription:CMFormatDescriptionRef?) {
        guard let
            formatDescription:CMFormatDescriptionRef = formatDescription,
            avcC:NSData = getData(formatDescription) else {
                return
        }
        
        let buffer:NSMutableData = NSMutableData()
        var data:[UInt8] = [UInt8](count: 5, repeatedValue: 0x00)
        // 1 Byte Frame Type & CodecID: 0x01 << 4 | 0x07
        data[0] = 0x01 << 4 | 0x07
        // 1Byte AVCPacketType -> 0x00
        data[1] = 0x00
        //data[2..4] -> COmposotion Time
        buffer.appendBytes(&data, length: data.count)
        // @see http://billhoo.blog.51cto.com/2337751/1557646
        // AVCDecoderConfigurationRecord Packet
        buffer.appendData(avcC)
        // Output AVC Sequence Header
        //
        var payload = [Int8](count: buffer.length, repeatedValue: 0x00)
        buffer.getBytes(&payload, length: payload.count)

        
        srs_rtmp!.srsRtmpWritePacket(0, data: &payload, size: Int32(payload.count))

    }
    
    
    private func getData(formatDescription:CMFormatDescriptionRef?) -> NSData? {
        guard let formatDescription:CMFormatDescriptionRef = formatDescription else {
            return nil
        }
        if let atoms:NSDictionary = CMFormatDescriptionGetExtension(formatDescription, "SampleDescriptionExtensionAtoms") as? NSDictionary {
            return atoms["avcC"] as? NSData
        }
        return nil
    }

    //
    private func sampleOutput(video sampleBuffer: CMSampleBuffer) {
        guard let block:CMBlockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else {
            return
        }
        
        let keyframe = !CFDictionaryContainsKey(unsafeBitCast(CFArrayGetValueAtIndex(CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, true), 0), CFDictionary.self), unsafeBitCast(kCMSampleAttachmentKey_NotSync, UnsafePointer<Void>.self))
        
        var totalLength:Int = 0
        var dataPointer:UnsafeMutablePointer<Int8> = nil
        CMBlockBufferGetDataPointer(block, 0, nil, &totalLength, &dataPointer)
        
        var cto:Int32 = 0
        let pts:CMTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        var dts:CMTime = CMSampleBufferGetDecodeTimeStamp(sampleBuffer)
        
        if (dts == kCMTimeInvalid) {
            dts = pts
        } else {
            cto = Int32((CMTimeGetSeconds(pts) - CMTimeGetSeconds(dts)) * 1000)
        }
        let delta:Double = (videoTimestamp == kCMTimeZero ? 0 : CMTimeGetSeconds(dts) - CMTimeGetSeconds(videoTimestamp)) * 1000
        let buffer:NSMutableData = NSMutableData()
        var data:[UInt8] = [UInt8](count: 5, repeatedValue: 0x00)
        
        
        data[0] = ((keyframe ? UInt8(0x01) : UInt8(0x02)) << 4) | UInt8(0x07)
        data[1] = UInt8(0x01)
        // CompositionTime
        data[2..<5] = cto.bigEndian.bytes[1..<4]
        buffer.appendBytes(&data, length: data.count)
        // H264 NALU Size + NALU Raw Data
        buffer.appendBytes(dataPointer, length: totalLength)
        
        // Output Common Flv Tag
        // delegate?.sampleOutput(self, video: buffer, timestamp: delta)
        
        var payload = [Int8](count: buffer.length, repeatedValue: 0x00)
        buffer.getBytes(&payload, length: payload.count)
        
        
        srs_rtmp!.srsRtmpWritePacket(Int32(realVideoTimeStamp), data: &payload, size: Int32(payload.count))
        realVideoTimeStamp += delta

        videoTimestamp = dts
    }
    
    let defaultAttributes:[NSString: AnyObject] = [
        
            kCVPixelBufferPixelFormatTypeKey: Int(kCVPixelFormatType_420YpCbCr8BiPlanarFullRange),
            kCVPixelBufferIOSurfacePropertiesKey: [:],
            kCVPixelBufferOpenGLESCompatibilityKey: true,
        ]
    private var width:Int32!
    private var height:Int32!
    
    private var attributes:[NSString: AnyObject] {
        var attributes:[NSString: AnyObject] = defaultAttributes
        attributes[kCVPixelBufferHeightKey] = 480
        attributes[kCVPixelBufferWidthKey] = 640
        return attributes
    }
    
    var profileLevel:String = kVTProfileLevel_H264_Baseline_3_1 as String
    private var properties:[NSString: NSObject] {
        let isBaseline:Bool = profileLevel.containsString("Baseline")
        var properties:[NSString: NSObject] = [
            kVTCompressionPropertyKey_RealTime: kCFBooleanTrue,
            kVTCompressionPropertyKey_ProfileLevel: profileLevel,
            kVTCompressionPropertyKey_AverageBitRate: Int(640*480),
            kVTCompressionPropertyKey_ExpectedFrameRate: NSNumber(double: 30.0),
            kVTCompressionPropertyKey_MaxKeyFrameIntervalDuration: NSNumber(double: 2.0),
            kVTCompressionPropertyKey_AllowFrameReordering: !isBaseline,
            kVTCompressionPropertyKey_PixelTransferProperties: [
                "ScalingMode": "Trim"
            ]
        ]
        if (!isBaseline) {
            properties[kVTCompressionPropertyKey_H264EntropyMode] = kVTH264EntropyMode_CABAC
        }
        return properties
    }

    
    override init() {
        super.init()
        VTCompressionSessionCreate(
            kCFAllocatorDefault,
            480, // encode height
            640,// encode width
            kCMVideoCodecType_H264,
            nil,
            attributes,
            nil,
            callback,
            unsafeBitCast(self, UnsafeMutablePointer<Void>.self),
            &session)
        
        VTSessionSetProperties(session!, properties)
        VTCompressionSessionPrepareToEncodeFrames(session!)
        
        // init filehandle
        let documentDir = NSSearchPathForDirectoriesInDomains(NSSearchPathDirectory.DocumentDirectory, NSSearchPathDomainMask.UserDomainMask, true)
        h264File = documentDir[0] + "/demo.h264"
        
        do {
            try NSFileManager.defaultManager().removeItemAtPath(h264File)
            try NSFileManager.defaultManager().createFileAtPath(h264File, contents: nil, attributes: nil)
            try fileHandle = NSFileHandle.init(forWritingToURL: NSURL(string: h264File)!)
        } catch let error as NSError {
            print(error)
        }
        
        // 开始 rtmp 连接
          srs_rtmp!.startRtmpSession()
    }
    
    func encodeImageBuffer(imageBuffer:CVImageBuffer, presentationTimeStamp:CMTime, presentationDuration:CMTime) {
        var flags:VTEncodeInfoFlags = VTEncodeInfoFlags()
    
        VTCompressionSessionEncodeFrame(session!, imageBuffer, presentationTimeStamp, presentationDuration, nil, nil, &flags)
    }
}


extension IntegerLiteralConvertible {
    var bytes:[UInt8] {
        var value:Self = self
        return withUnsafePointer(&value) {
            Array(UnsafeBufferPointer(start: UnsafePointer<UInt8>($0), count: sizeof(Self.self)))
        }
    }
    
    init(bytes:[UInt8]) {
        self = bytes.withUnsafeBufferPointer {
            return UnsafePointer<`Self`>($0.baseAddress).memory
        }
    }
}
