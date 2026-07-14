import Flutter
import UIKit
import AVFoundation
import Vision

class CameraPreviewView: UIView {
    var onLayoutChanged: (() -> Void)?

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
        onLayoutChanged?()
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
    
    // Cached orientation state
    private var cachedCGImageOrientation: CGImagePropertyOrientation = .right
    private let orientationLock = NSLock()

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
        
        // Cache initial orientation and register layout callback
        updateOrientationCache()
        self._view.onLayoutChanged = { [weak self] in
            self?.updateOrientationCache()
        }
        
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
                    videoCaptureDevice.autoFocusRangeRestriction = .none
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
            let desiredZoom: CGFloat = 2.0
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
        
        // Read cached orientation thread-safely
        self.orientationLock.lock()
        let cgOrientation = self.cachedCGImageOrientation
        self.orientationLock.unlock()
        
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            
            // Run VNDetectBarcodesRequest for high-performance deep-learning barcode recognition
            // Pass the image orientation to the handler so Vision internally uprights the frame
            let requestHandler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: cgOrientation, options: [:])
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
                
                // Determine upright dimensions directly from the raw pixel buffer
                let pWidth = Double(CVPixelBufferGetWidth(pixelBuffer))
                let pHeight = Double(CVPixelBufferGetHeight(pixelBuffer))
                let isPortrait = (cgOrientation == .right || cgOrientation == .left)
                let imgWidth = isPortrait ? pHeight : pWidth
                let imgHeight = isPortrait ? pWidth : pHeight
                
                // Crop and generate JPEG bytes in the background thread (since CIContext is CPU/GPU intensive)
                var imageBytes: FlutterStandardTypedData? = nil
                if self.enableImageCapture {
                    let ciContext = CIContext()
                    let ciImage = CIImage(cvPixelBuffer: pixelBuffer).oriented(cgOrientation)
                    if let cgImage = ciContext.createCGImage(ciImage, from: ciImage.extent) {
                        let uiImage = UIImage(cgImage: cgImage)
                        if let jpegData = uiImage.jpegData(compressionQuality: 0.8) {
                            imageBytes = FlutterStandardTypedData(bytes: jpegData)
                        }
                    }
                }
                
                // Dispatch to main thread to perform UIKit bounds lookup and fire eventSink safely
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
                    
                    // Map from Vision's uncropped normalized output space to screen preview aspect-fill space
                    let scaleX = viewWidth / imgWidth
                    let scaleY = viewHeight / imgHeight
                    let scale = max(scaleX, scaleY)
                    let dx = (imgWidth * scale - viewWidth) / 2.0
                    let dy = (imgHeight * scale - viewHeight) / 2.0
                    
                    for observation in observations {
                        guard let stringValue = observation.payloadStringValue else { continue }
                        
                        // Map normalized coordinates from Vision (origin bottom-left) directly to upright image space coordinates:
                        // pt.x = normX * imgWidth
                        // pt.y = (1.0 - normY) * imgHeight (to invert bottom-left to top-left)
                        let rawCorners = [observation.topLeft, observation.topRight, observation.bottomRight, observation.bottomLeft]
                        
                        let imageCorners = rawCorners.map { point -> [String: Double] in
                            let imgX = point.x * imgWidth
                            let imgY = (1.0 - point.y) * imgHeight
                            return ["x": imgX, "y": imgY]
                        }
                        
                        if imageCorners.count < 4 { continue }
                        
                        // Project to screen preview coordinates using direct aspect-fill math (same as Dart side)
                        // for native scan window validation check
                        let screenCorners = rawCorners.map { point -> CGPoint in
                            let px = point.x * imgWidth * scale - dx
                            let py = (1.0 - point.y) * imgHeight * scale - dy
                            return CGPoint(x: px, y: py)
                        }
                        
                        // Native Scan Window Containment Check
                        if let swWidth = self.scanWindowWidthFactor, let swHeight = self.scanWindowHeightFactor {
                            let xMin = 0.5 - swWidth / 2.0
                            let xMax = 0.5 + swWidth / 2.0
                            let yMin = 0.5 - swHeight / 2.0
                            let yMax = 0.5 + swHeight / 2.0
                            
                            // Ensure all corners are fully inside the scan window to prevent partial/half-visible scans
                            let allInside = screenCorners.allSatisfy { pt in
                                let normX = Double(pt.x) / viewWidth
                                let normY = Double(pt.y) / viewHeight
                                return normX >= xMin && normX <= xMax && normY >= yMin && normY <= yMax
                            }
                            
                            if !allInside {
                                continue // Skip barcode that is not fully inside the scan window
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
                            "corners": imageCorners, // Report coordinates in uncropped upright image space
                            "imageWidth": Int(imgWidth),
                            "imageHeight": Int(imgHeight)
                        ]
                        
                        if let bytes = imageBytes {
                            result["imageBytes"] = bytes
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
        
        // Cache the updated camera orientation
        self.updateOrientationCache()
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
                    device.autoFocusRangeRestriction = .none
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

    private func updateOrientationCache() {
        let orientation: AVCaptureVideoOrientation
        if let previewOrientation = _view.videoPreviewLayer.connection?.videoOrientation {
            orientation = previewOrientation
        } else {
            orientation = .portrait
        }
        
        let cgOrientation: CGImagePropertyOrientation
        switch orientation {
        case .portrait: cgOrientation = .right
        case .landscapeRight: cgOrientation = .up
        case .landscapeLeft: cgOrientation = .down
        case .portraitUpsideDown: cgOrientation = .left
        @unknown default: cgOrientation = .right
        }
        
        self.orientationLock.lock()
        self.cachedCGImageOrientation = cgOrientation
        self.orientationLock.unlock()
    }
}
