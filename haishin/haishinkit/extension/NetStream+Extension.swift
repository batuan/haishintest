import AVFoundation
import Foundation

extension NetStream {
    open var orientation: AVCaptureVideoOrientation {
        get {
            return mixer.videoIO.orientation
        }
        set {
            self.mixer.videoIO.orientation = newValue
        }
    }
}
