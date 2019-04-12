import AVFoundation
import CoreImage
import UIKit
final class VideoIOComponent: IOComponent {
    #if os(macOS)
    static let defaultAttributes: [NSString: NSObject] = [
        kCVPixelBufferPixelFormatTypeKey: NSNumber(value: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange),
        kCVPixelBufferMetalCompatibilityKey: kCFBooleanTrue,
        kCVPixelBufferOpenGLCompatibilityKey: kCFBooleanTrue
    ]
    #else
    static let defaultAttributes: [NSString: NSObject] = [
        kCVPixelBufferPixelFormatTypeKey: NSNumber(value: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange),
        kCVPixelBufferMetalCompatibilityKey: kCFBooleanTrue,
        kCVPixelBufferOpenGLESCompatibilityKey: kCFBooleanTrue
    ]
    #endif

    let lockQueue = DispatchQueue(label: "com.haishinkit.HaishinKit.VideoIOComponent.lock")

    #if os(iOS) || os(macOS)
    var drawable: NetStreamDrawable? = nil {
        didSet {
            drawable?.orientation = orientation
        }
    }
    #else
    var drawable: NetStreamDrawable? = nil
    #endif

    var formatDescription: CMVideoFormatDescription? {
        didSet {
            decoder.formatDescription = formatDescription
        }
    }
    var encoder = H264Encoder()
    var decoder = H264Decoder()
    lazy var queue: DisplayLinkedQueue = {
        let queue = DisplayLinkedQueue()
        queue.delegate = self
        return queue
    }()

    private var extent = CGRect.zero {
        didSet {
            guard extent != oldValue else {
                return
            }
            pixelBufferPool = nil
        }
    }

    private var attributes: [NSString: NSObject] {
        var attributes: [NSString: NSObject] = VideoIOComponent.defaultAttributes
        attributes[kCVPixelBufferWidthKey] = NSNumber(value: Int(extent.width))
        attributes[kCVPixelBufferHeightKey] = NSNumber(value: Int(extent.height))
        return attributes
    }

    private var _pixelBufferPool: CVPixelBufferPool?
    private var pixelBufferPool: CVPixelBufferPool! {
        get {
            if _pixelBufferPool == nil {
                var pixelBufferPool: CVPixelBufferPool?
                CVPixelBufferPoolCreate(nil, nil, attributes as CFDictionary?, &pixelBufferPool)
                _pixelBufferPool = pixelBufferPool
            }
            return _pixelBufferPool!
        }
        set {
            _pixelBufferPool = newValue
        }
    }

    #if os(iOS) || os(macOS)
    var fps: Float64 = AVMixer.defaultFPS
//    var videoSettings: [NSObject: AnyObject] = AVMixer.defaultVideoSettings {
//        didSet {
//            output.videoSettings = videoSettings as? [String: Any]
//        }
//    }

    var orientation: AVCaptureVideoOrientation = .portrait
    var torch: Bool = false {
        didSet {
            guard torch != oldValue else {
                return
            }
        }
    }



//    private var _output: AVCaptureVideoDataOutput?
//    var output: AVCaptureVideoDataOutput! {
//        get {
//            if _output == nil {
//                _output = AVCaptureVideoDataOutput()
//                _output?.alwaysDiscardsLateVideoFrames = true
//                _output?.videoSettings = videoSettings as? [String: Any]
//            }
//            return _output!
//        }
//        set {
//            if _output == newValue {
//                return
//            }
//            if let output: AVCaptureVideoDataOutput = _output {
//                output.setSampleBufferDelegate(nil, queue: nil)
//                mixer?.session.removeOutput(output)
//            }
//            _output = newValue
//        }
//    }

    var input: AVCaptureInput? = nil {
        didSet {
            guard let mixer: AVMixer = mixer, oldValue != input else {
                return
            }
            if let oldValue: AVCaptureInput = oldValue {
                //mixer.session.removeInput(oldValue)
            }
            if let input: AVCaptureInput = input, mixer.session.canAddInput(input) {
                mixer.session.addInput(input)
            }
        }
    }
    #endif


    override init(mixer: AVMixer) {
        super.init(mixer: mixer)
        encoder.lockQueue = lockQueue
        decoder.delegate = self
        #if os(iOS)
        if let orientation: AVCaptureVideoOrientation = DeviceUtil.videoOrientation(by: UIDevice.current.orientation) {
            self.orientation = orientation
        } else if let defaultOrientation = RTMPStream.defaultOrientation {
            self.orientation = defaultOrientation
        }
        #endif
    }

    func appendSampleBuffer(_ sampleBuffer: CMSampleBuffer) {
        guard let buffer: CVImageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            return
        }

        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }

        var imageBuffer: CVImageBuffer?



        encoder.encodeImageBuffer(
            imageBuffer ?? buffer,
            presentationTimeStamp: sampleBuffer.presentationTimeStamp,
            duration: sampleBuffer.duration
        )

        mixer?.recorder.appendPixelBuffer(imageBuffer ?? buffer, withPresentationTime: sampleBuffer.presentationTimeStamp)
    }
}

extension VideoIOComponent: VideoDecoderDelegate {
    // MARK: VideoDecoderDelegate
    func sampleOutput(video sampleBuffer: CMSampleBuffer) {
        queue.enqueue(sampleBuffer)
    }
}

extension VideoIOComponent: DisplayLinkedQueueDelegate {
    // MARK: DisplayLinkedQueue
    func queue(_ buffer: CMSampleBuffer) {
        drawable?.draw(image: CIImage(cvPixelBuffer: buffer.imageBuffer!))
    }
}
