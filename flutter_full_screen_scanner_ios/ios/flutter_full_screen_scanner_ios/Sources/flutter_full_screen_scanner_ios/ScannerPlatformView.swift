import Flutter
import UIKit
import AVFoundation

class CameraPreviewView: UIView {
    override class var layerClass: AnyClass {
        return AVCaptureVideoPreviewLayer.self
    }
    var videoPreviewLayer: AVCaptureVideoPreviewLayer {
        return layer as! AVCaptureVideoPreviewLayer
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        
        if let connection = videoPreviewLayer.connection, connection.isVideoOrientationSupported {
            if #available(iOS 13.0, *) {
                let interfaceOrientation = self.window?.windowScene?.interfaceOrientation
                switch interfaceOrientation {
                case .portrait:
                    connection.videoOrientation = .portrait
                case .landscapeRight:
                    connection.videoOrientation = .landscapeRight
                case .landscapeLeft:
                    connection.videoOrientation = .landscapeLeft
                case .portraitUpsideDown:
                    connection.videoOrientation = .portraitUpsideDown
                default:
                    connection.videoOrientation = .portrait
                }
            } else {
                let orientation = UIApplication.shared.statusBarOrientation
                switch orientation {
                case .portrait:
                    connection.videoOrientation = .portrait
                case .landscapeRight:
                    connection.videoOrientation = .landscapeRight
                case .landscapeLeft:
                    connection.videoOrientation = .landscapeLeft
                case .portraitUpsideDown:
                    connection.videoOrientation = .portraitUpsideDown
                default:
                    connection.videoOrientation = .portrait
                }
            }
        }
    }
}

class ScannerPlatformView: NSObject, FlutterPlatformView, AVCaptureMetadataOutputObjectsDelegate, AVCaptureVideoDataOutputSampleBufferDelegate {
    private var _view: CameraPreviewView
    private var plugin: FlutterFullScreenScannerIosPlugin
    private var captureSession: AVCaptureSession?
    private var latestPixelBuffer: CVPixelBuffer?
    
    // Duplicate prevention
    private var allowDuplicate: Bool = false
    private var duplicateDelay: Int = 1500
    private var scannedCache: [String: TimeInterval] = [:]
    
    private var pendingBarcodeData: [String: Any]? = nil

    init(
        frame: CGRect,
        viewIdentifier viewId: Int64,
        arguments args: Any?,
        plugin: FlutterFullScreenScannerIosPlugin
    ) {
        self._view = CameraPreviewView(frame: frame)
        self.plugin = plugin
        
        if let params = args as? [String: Any] {
            if let allow = params["allowDuplicate"] as? Bool {
                self.allowDuplicate = allow
            }
            if let delay = params["duplicateDelay"] as? Int {
                self.duplicateDelay = delay
            }
        }
        
        super.init()
        setupCamera()
    }

    func view() -> UIView {
        return _view
    }

    private func setupCamera() {
        captureSession = AVCaptureSession()
        guard let captureSession = captureSession else { return }
        
        if captureSession.canSetSessionPreset(.hd1920x1080) {
            captureSession.sessionPreset = .hd1920x1080
        } else if captureSession.canSetSessionPreset(.high) {
            captureSession.sessionPreset = .high
        }

        guard let videoCaptureDevice = AVCaptureDevice.default(for: .video) else { return }
        
        // Enable continuous auto-focus to ensure sharp images
        do {
            try videoCaptureDevice.lockForConfiguration()
            if videoCaptureDevice.isFocusModeSupported(.continuousAutoFocus) {
                videoCaptureDevice.focusMode = .continuousAutoFocus
            }
            if videoCaptureDevice.isExposureModeSupported(.continuousAutoExposure) {
                videoCaptureDevice.exposureMode = .continuousAutoExposure
            }
            videoCaptureDevice.unlockForConfiguration()
        } catch {
            print("Failed to configure focus/exposure.")
        }

        let videoInput: AVCaptureDeviceInput

        do {
            videoInput = try AVCaptureDeviceInput(device: videoCaptureDevice)
        } catch {
            return
        }

        if (captureSession.canAddInput(videoInput)) {
            captureSession.addInput(videoInput)
        } else {
            return
        }

        let metadataOutput = AVCaptureMetadataOutput()
        if (captureSession.canAddOutput(metadataOutput)) {
            captureSession.addOutput(metadataOutput)
            metadataOutput.setMetadataObjectsDelegate(self, queue: DispatchQueue.main)
            metadataOutput.metadataObjectTypes = [.qr, .ean8, .ean13, .pdf417, .code128, .code39, .code93, .itf14, .dataMatrix, .aztec]
        } else {
            return
        }

        let videoOutput = AVCaptureVideoDataOutput()
        videoOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA)]
        if captureSession.canAddOutput(videoOutput) {
            captureSession.addOutput(videoOutput)
            videoOutput.setSampleBufferDelegate(self, queue: DispatchQueue(label: "videoQueue"))
        }

        _view.videoPreviewLayer.session = captureSession
        _view.videoPreviewLayer.videoGravity = .resizeAspectFill

        DispatchQueue.global(qos: .background).async {
            captureSession.startRunning()
        }
    }

    func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput metadataObjects: [AVMetadataObject], from connection: AVCaptureConnection) {
        if let metadataObject = metadataObjects.first {
            guard let readableObject = metadataObject as? AVMetadataMachineReadableCodeObject else { return }
            guard let stringValue = readableObject.stringValue else { return }
            
            let currentTime = Date().timeIntervalSince1970 * 1000
            
            if (!allowDuplicate) {
                if let lastScanTime = scannedCache[stringValue], (currentTime - lastScanTime) < Double(duplicateDelay) {
                    return
                }
            }
            scannedCache[stringValue] = currentTime
            
            // Determine current orientation
            let currentOrientation = _view.videoPreviewLayer.connection?.videoOrientation ?? .portrait
            
            // Map Vision normalized coordinates (0..1) back to pixel coordinates based on orientation
            var corners: [[String: Double]] = []
            if !readableObject.corners.isEmpty {
                for point in readableObject.corners {
                    switch currentOrientation {
                    case .portrait:
                        corners.append(["x": Double(1.0 - point.y), "y": Double(point.x)])
                    case .landscapeRight:
                        corners.append(["x": Double(point.x), "y": Double(point.y)])
                    case .landscapeLeft:
                        corners.append(["x": Double(1.0 - point.x), "y": Double(1.0 - point.y)])
                    case .portraitUpsideDown:
                        corners.append(["x": Double(point.y), "y": Double(1.0 - point.x)])
                    @unknown default:
                        corners.append(["x": Double(1.0 - point.y), "y": Double(point.x)])
                    }
                }
            }
            
            var result: [String: Any] = [
                "value": stringValue,
                "type": readableObject.type.rawValue,
                "timestamp": Int(currentTime),
                "corners": corners
            ]
            
            // Pass the current orientation to the capture thread
            result["orientation"] = _view.videoPreviewLayer.connection?.videoOrientation.rawValue ?? AVCaptureVideoOrientation.portrait.rawValue
            
            // Request the next frame to grab the image bytes
            self.pendingBarcodeData = result
        }
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        if let pending = self.pendingBarcodeData {
            self.pendingBarcodeData = nil
            
            var result = pending
            
            if let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) {
                let orientationRaw = pending["orientation"] as? Int ?? AVCaptureVideoOrientation.portrait.rawValue
                let orientation = AVCaptureVideoOrientation(rawValue: orientationRaw) ?? .portrait
                
                var ciOrientation: CGImagePropertyOrientation = .right
                switch orientation {
                case .portrait: ciOrientation = .right
                case .landscapeRight: ciOrientation = .up
                case .landscapeLeft: ciOrientation = .down
                case .portraitUpsideDown: ciOrientation = .left
                @unknown default: ciOrientation = .right
                }
                
                let ciImage = CIImage(cvPixelBuffer: pixelBuffer).oriented(ciOrientation)
                let context = CIContext()
                if let cgImage = context.createCGImage(ciImage, from: ciImage.extent) {
                    let uiImage = UIImage(cgImage: cgImage)
                    if let jpegData = uiImage.jpegData(compressionQuality: 1.0) {
                        result["imageBytes"] = FlutterStandardTypedData(bytes: jpegData)
                        result["imageWidth"] = Int(uiImage.size.width)
                        result["imageHeight"] = Int(uiImage.size.height)
                        
                        // Fix corners scaling since bounds were normalized 0..1
                        if let corners = result["corners"] as? [[String: Double]] {
                            let w = Double(uiImage.size.width)
                            let h = Double(uiImage.size.height)
                            let scaledCorners = corners.map { ["x": $0["x"]! * w, "y": $0["y"]! * h] }
                            result["corners"] = scaledCorners
                        }
                    }
                }
            }
            
            DispatchQueue.main.async {
                self.plugin.eventSink?([
                    "type": "scanned",
                    "data": [result]
                ])
            }
        }
    }

    func pause() {
        captureSession?.stopRunning()
    }

    func resume() {
        DispatchQueue.global(qos: .background).async {
            self.captureSession?.startRunning()
        }
    }

    func stop() {
        captureSession?.stopRunning()
    }

    func toggleFlash() -> Bool {
        guard let device = AVCaptureDevice.default(for: .video), device.hasTorch else { return false }
        do {
            try device.lockForConfiguration()
            let isOn = device.torchMode == .on
            device.torchMode = isOn ? .off : .on
            device.unlockForConfiguration()
            return !isOn
        } catch {
            return false
        }
    }

    func switchCamera() {
        guard let session = captureSession else { return }
        session.beginConfiguration()
        guard let currentInput = session.inputs.first as? AVCaptureDeviceInput else { return }
        session.removeInput(currentInput)

        let newPosition: AVCaptureDevice.Position = currentInput.device.position == .back ? .front : .back
        guard let newDevice = AVCaptureDevice.DiscoverySession(deviceTypes: [.builtInWideAngleCamera], mediaType: .video, position: newPosition).devices.first else { return }
        
        do {
            let newInput = try AVCaptureDeviceInput(device: newDevice)
            if session.canAddInput(newInput) {
                session.addInput(newInput)
            }
        } catch {
            print("Failed to switch camera.")
        }
        session.commitConfiguration()
    }

    func focusAt(x: Double, y: Double) {
        guard let device = AVCaptureDevice.default(for: .video) else { return }
        do {
            try device.lockForConfiguration()
            if device.isFocusPointOfInterestSupported && device.isFocusModeSupported(.autoFocus) {
                device.focusPointOfInterest = CGPoint(x: x, y: y)
                device.focusMode = .autoFocus
            }
            device.unlockForConfiguration()
        } catch {
            print("Failed to focus.")
        }
    }
    
    func dispose() {
        if let session = captureSession {
            if session.isRunning {
                session.stopRunning()
            }
            for input in session.inputs {
                session.removeInput(input)
            }
            for output in session.outputs {
                session.removeOutput(output)
            }
        }
        _view.videoPreviewLayer.session = nil
        captureSession = nil
        scannedCache.removeAll()
    }
}
