import Flutter
import UIKit
import AVFoundation
import Vision

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

class ScannerPlatformView: NSObject, FlutterPlatformView, AVCaptureVideoDataOutputSampleBufferDelegate {
    private var _view: CameraPreviewView
    private var plugin: FlutterFullScreenScannerIosPlugin
    private var captureSession: AVCaptureSession?
    
    // Duplicate prevention
    private var allowDuplicate: Bool = false
    private var duplicateDelay: Int = 1500
    private var scannedCache: [String: TimeInterval] = [:]
    
    private var enableImageCapture: Bool = true
    private var scanWindowWidthFactor: Double? = nil
    private var scanWindowHeightFactor: Double? = nil
    
    private var videoDevice: AVCaptureDevice?
    private var subjectAreaChangeObserver: NSObjectProtocol?
    private var imagesCurrentlyBeingProcessed = false

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
            if let enableCapture = params["enableImageCapture"] as? Bool {
                self.enableImageCapture = enableCapture
            }
            if let swWidth = params["scanWindowWidthFactor"] as? Double {
                self.scanWindowWidthFactor = swWidth
            }
            if let swHeight = params["scanWindowHeightFactor"] as? Double {
                self.scanWindowHeightFactor = swHeight
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
        
        if captureSession.canSetSessionPreset(.high) {
            captureSession.sessionPreset = .high
        }

        guard let videoCaptureDevice = AVCaptureDevice.default(for: .video) else { return }
        self.videoDevice = videoCaptureDevice
        
        // Enable continuous auto-focus and subject monitoring for maximum clarity
        do {
            try videoCaptureDevice.lockForConfiguration()
            if videoCaptureDevice.isFocusModeSupported(.continuousAutoFocus) {
                videoCaptureDevice.focusMode = .continuousAutoFocus
                if videoCaptureDevice.isAutoFocusRangeRestrictionSupported {
                    videoCaptureDevice.autoFocusRangeRestriction = .near
                }
                if videoCaptureDevice.isFocusPointOfInterestSupported {
                    videoCaptureDevice.focusPointOfInterest = CGPoint(x: 0.5, y: 0.5)
                }
            }
            if videoCaptureDevice.isExposureModeSupported(.continuousAutoExposure) {
                videoCaptureDevice.exposureMode = .continuousAutoExposure
                if videoCaptureDevice.isExposurePointOfInterestSupported {
                    videoCaptureDevice.exposurePointOfInterest = CGPoint(x: 0.5, y: 0.5)
                }
            }
            videoCaptureDevice.isSubjectAreaChangeMonitoringEnabled = true
            
            // Zoom in slightly so the user holds the phone at a comfortable distance (improving focus)
            let desiredZoom: CGFloat = 1.5
            videoCaptureDevice.videoZoomFactor = min(desiredZoom, videoCaptureDevice.activeFormat.videoMaxZoomFactor)
            
            videoCaptureDevice.unlockForConfiguration()
        } catch {
            print("Failed to configure focus/exposure.")
        }

        // Listen to subject area changes to trigger re-focus immediately
        self.subjectAreaChangeObserver = NotificationCenter.default.addObserver(
            forName: NSNotification.Name.AVCaptureDeviceSubjectAreaDidChange,
            object: videoCaptureDevice,
            queue: .main
        ) { [weak self] _ in
            self?.resetFocus()
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

        // Set up the sample buffer video output for Vision framework processing
        let videoOutput = AVCaptureVideoDataOutput()
        videoOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA)]
        videoOutput.alwaysDiscardsLateVideoFrames = true
        if captureSession.canAddOutput(videoOutput) {
            captureSession.addOutput(videoOutput)
            let queue = DispatchQueue(label: "com.example.flutter_full_screen_scanner.captureOutputQueue", qos: .userInitiated)
            videoOutput.setSampleBufferDelegate(self, queue: queue)
        }

        _view.videoPreviewLayer.session = captureSession
        _view.videoPreviewLayer.videoGravity = .resizeAspectFill

        DispatchQueue.global(qos: .background).async {
            captureSession.startRunning()
        }
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        
        if imagesCurrentlyBeingProcessed {
            return
        }
        imagesCurrentlyBeingProcessed = true
        
        let currentTime = Date().timeIntervalSince1970 * 1000
        
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            
            // Run VNDetectBarcodesRequest for high-performance deep-learning barcode recognition
            let requestHandler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, options: [:])
            let request = VNDetectBarcodesRequest { [weak self] request, error in
                guard let self = self else { return }
                
                if let error = error {
                    print("Vision error: \(error.localizedDescription)")
                }
                
                guard let observations = request.results as? [VNBarcodeObservation] else {
                    self.imagesCurrentlyBeingProcessed = false
                    return
                }
                if observations.isEmpty {
                    self.imagesCurrentlyBeingProcessed = false
                    return
                }
                
                // Crop and generate JPEG bytes in the background thread (since CIContext is CPU/GPU intensive)
                var imageBytes: FlutterStandardTypedData? = nil
                var imgWidth = 0.0
                var imgHeight = 0.0
                if self.enableImageCapture {
                    var ciOrientation: CGImagePropertyOrientation = .right
                    DispatchQueue.main.sync {
                        if let orientation = self._view.videoPreviewLayer.connection?.videoOrientation {
                            switch orientation {
                            case .portrait: ciOrientation = .right
                            case .landscapeRight: ciOrientation = .up
                            case .landscapeLeft: ciOrientation = .down
                            case .portraitUpsideDown: ciOrientation = .left
                            @unknown default: ciOrientation = .right
                            }
                        }
                    }
                    
                    let ciContext = CIContext()
                    let ciImage = CIImage(cvPixelBuffer: pixelBuffer).oriented(ciOrientation)
                    if let cgImage = ciContext.createCGImage(ciImage, from: ciImage.extent) {
                        let uiImage = UIImage(cgImage: cgImage)
                        imgWidth = Double(uiImage.size.width)
                        imgHeight = Double(uiImage.size.height)
                        if let jpegData = uiImage.jpegData(compressionQuality: 0.8) {
                            imageBytes = FlutterStandardTypedData(bytes: jpegData)
                        }
                    }
                }
                
                // Dispatch to main thread to perform UIKit coordinate translation safely
                DispatchQueue.main.async { [weak self] in
                    guard let self = self else { return }
                    defer {
                        self.imagesCurrentlyBeingProcessed = false
                    }
                    
                    let bounds = self._view.bounds
                    let viewWidth = Double(bounds.width)
                    let viewHeight = Double(bounds.height)
                    
                    guard viewWidth > 0 && viewHeight > 0 else { return }
                    
                    var finalResults: [[String: Any]] = []
                    
                    for observation in observations {
                        guard let stringValue = observation.payloadStringValue else { continue }
                        
                        // Map normalized Vision coordinates (origin bottom-left) to logical screen space (origin top-left)
                        // using built-in preview layer coordinate transformer
                        let corners = [observation.topLeft, observation.topRight, observation.bottomRight, observation.bottomLeft].map { point -> [String: Double] in
                            let devicePoint = CGPoint(x: point.x, y: 1.0 - point.y)
                            let screenPoint = self._view.videoPreviewLayer.layerPointConverted(fromCaptureDevicePoint: devicePoint)
                            return ["x": Double(screenPoint.x), "y": Double(screenPoint.y)]
                        }
                        
                        if corners.count < 4 { continue }
                        
                        // Native Scan Window Containment Check
                        if let swWidth = self.scanWindowWidthFactor, let swHeight = self.scanWindowHeightFactor {
                            let xMin = 0.5 - swWidth / 2.0
                            let xMax = 0.5 + swWidth / 2.0
                            let yMin = 0.5 - swHeight / 2.0
                            let yMax = 0.5 + swHeight / 2.0
                            
                            // Calculate centroid in screen pixels
                            var sumX = 0.0
                            var sumY = 0.0
                            for pt in corners {
                                sumX += pt["x"]!
                                sumY += pt["y"]!
                            }
                            let centroidX = sumX / Double(corners.count)
                            let centroidY = sumY / Double(corners.count)
                            
                            // Normalize centroid relative to screen layout bounds
                            let normX = centroidX / viewWidth
                            let normY = centroidY / viewHeight
                            
                            if normX < xMin || normX > xMax || normY < yMin || normY > yMax {
                                continue // Skip barcode outside orange scan window
                            }
                        }
                        
                        // Duplicate prevention
                        if (!self.allowDuplicate) {
                            if let lastScanTime = self.scannedCache[stringValue], (currentTime - lastScanTime) < Double(self.duplicateDelay) {
                                continue
                            }
                        }
                        
                        self.scannedCache[stringValue] = currentTime
                        
                        let barcodeType = self.mapVisionSymbologyToMetadataType(observation.symbology)
                        
                        var result: [String: Any] = [
                            "value": stringValue,
                            "type": barcodeType,
                            "timestamp": Int(currentTime),
                            "corners": corners,
                            "imageWidth": Int(viewWidth),
                            "imageHeight": Int(viewHeight)
                        ]
                        
                        if let bytes = imageBytes {
                            result["imageBytes"] = bytes
                            result["imageWidth"] = Int(imgWidth)
                            result["imageHeight"] = Int(imgHeight)
                            
                            let scaledCorners = corners.map { pt -> [String: Double] in
                                let normX = pt["x"]! / viewWidth
                                let normY = pt["y"]! / viewHeight
                                return ["x": normX * imgWidth, "y": normY * imgHeight]
                            }
                            result["corners"] = scaledCorners
                        }
                        
                        finalResults.append(result)
                    }
                    
                    if !finalResults.isEmpty {
                        self.plugin.eventSink?([
                            "type": "scanned",
                            "data": finalResults
                        ])
                    }
                }
            }
            
            request.symbologies = [.code128, .qr, .ean8, .ean13, .pdf417, .code39, .code93, .itf14, .dataMatrix, .aztec]
            do {
                try requestHandler.perform([request])
            } catch {
                print("Vision perform error: \(error.localizedDescription)")
                self.imagesCurrentlyBeingProcessed = false
            }
        }
    }
    
    private func mapVisionSymbologyToMetadataType(_ symbology: VNBarcodeSymbology) -> String {
        switch symbology {
        case .code128: return AVMetadataObject.ObjectType.code128.rawValue
        case .qr: return AVMetadataObject.ObjectType.qr.rawValue
        case .ean8: return AVMetadataObject.ObjectType.ean8.rawValue
        case .ean13: return AVMetadataObject.ObjectType.ean13.rawValue
        case .pdf417: return AVMetadataObject.ObjectType.pdf417.rawValue
        case .code39: return AVMetadataObject.ObjectType.code39.rawValue
        case .code93: return AVMetadataObject.ObjectType.code93.rawValue
        case .itf14: return AVMetadataObject.ObjectType.itf14.rawValue
        case .dataMatrix: return AVMetadataObject.ObjectType.dataMatrix.rawValue
        case .aztec: return AVMetadataObject.ObjectType.aztec.rawValue
        default: return symbology.rawValue
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
        if let observer = subjectAreaChangeObserver {
            NotificationCenter.default.removeObserver(observer)
            subjectAreaChangeObserver = nil
        }
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

    private func resetFocus() {
        guard let device = videoDevice else { return }
        do {
            try device.lockForConfiguration()
            if device.isFocusModeSupported(.continuousAutoFocus) {
                device.focusMode = .continuousAutoFocus
                if device.isAutoFocusRangeRestrictionSupported {
                    device.autoFocusRangeRestriction = .near
                }
                if device.isFocusPointOfInterestSupported {
                    device.focusPointOfInterest = CGPoint(x: 0.5, y: 0.5)
                }
            }
            if device.isExposureModeSupported(.continuousAutoExposure) {
                device.exposureMode = .continuousAutoExposure
                if device.isExposurePointOfInterestSupported {
                    device.exposurePointOfInterest = CGPoint(x: 0.5, y: 0.5)
                }
            }
            device.unlockForConfiguration()
        } catch {
            print("Failed to reset focus on subject area change.")
        }
    }
}
