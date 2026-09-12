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
    private var rejectBlurryImages: Bool = false
    private var blurThreshold: Double = 35.0
    /// nil = no cap; set via maxExposureDurationSeconds to trade low-light brightness for less motion blur.
    private var maxExposureDurationSeconds: Double? = nil
    /// Empty = all formats (default); non-empty = Vision restricted to only these symbologies.
    private var configuredSymbologies: [VNBarcodeSymbology] = []

    private var videoDevice: AVCaptureDevice?
    private var subjectAreaChangeObserver: NSObjectProtocol?
    private var imagesCurrentlyBeingProcessed = false
    
    // Cached orientation and size state
    private var cachedCGImageOrientation: CGImagePropertyOrientation = .right
    private var cachedViewWidth: Double = 0.0
    private var cachedViewHeight: Double = 0.0
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
            if let rejectBlurry = params["rejectBlurryImages"] as? Bool {
                self.rejectBlurryImages = rejectBlurry
            }
            if let threshold = params["blurThreshold"] as? Double {
                self.blurThreshold = threshold
            }
            if let maxExp = params["maxExposureDurationSeconds"] as? Double {
                self.maxExposureDurationSeconds = maxExp
            }
            if let formats = params["supportedFormats"] as? [String] {
                self.configuredSymbologies = ScannerPlatformView.symbologiesFromFormatNames(formats)
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
                // Opt-in cap: clamps AE shutter to reduce motion blur in dim light; nil = no cap (default).
                if let maxSeconds = self.maxExposureDurationSeconds, maxSeconds > 0 {
                    let maxDuration = CMTimeMakeWithSeconds(maxSeconds, preferredTimescale: 1_000_000)
                    let clamped = CMTimeMinimum(maxDuration, videoCaptureDevice.activeFormat.maxExposureDuration)
                    videoCaptureDevice.activeMaxExposureDuration = clamped
                }
            }
            videoCaptureDevice.isSubjectAreaChangeMonitoringEnabled = true
            
            // Zoom in slightly so the user holds the phone at a comfortable distance (improving focus)
            let desiredZoom: CGFloat = 1.0
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
            if let connection = videoOutput.connections.first,
               connection.isVideoStabilizationSupported {
                connection.preferredVideoStabilizationMode = .auto
            }
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
                
                // Thread-safely get cached view width/height
                self.orientationLock.lock()
                let viewWidth = self.cachedViewWidth
                let viewHeight = self.cachedViewHeight
                self.orientationLock.unlock()
                
                var acceptedEntries: [(observation: VNBarcodeObservation, stringValue: String, imageCorners: [[String: Double]])] = []
                
                if viewWidth > 0 && viewHeight > 0 {
                    let scaleX = viewWidth / imgWidth
                    let scaleY = viewHeight / imgHeight
                    let scale = max(scaleX, scaleY)
                    let dx = (imgWidth * scale - viewWidth) / 2.0
                    let dy = (imgHeight * scale - viewHeight) / 2.0
                    
                    for observation in observations {
                        guard let stringValue = observation.payloadStringValue else { continue }
                        
                        let rawCorners = [observation.topLeft, observation.topRight, observation.bottomRight, observation.bottomLeft]
                        let imageCorners = rawCorners.map { point -> [String: Double] in
                            let imgX = point.x * imgWidth
                            let imgY = (1.0 - point.y) * imgHeight
                            return ["x": imgX, "y": imgY]
                        }
                        if imageCorners.count < 4 { continue }
                        
                        let screenCorners = rawCorners.map { point -> CGPoint in
                            let px = point.x * imgWidth * scale - dx
                            let py = (1.0 - point.y) * imgHeight * scale - dy
                            return CGPoint(x: px, y: py)
                        }
                        
                        // Native Scan Window Containment Check
                        if let swWidth = self.scanWindowWidthFactor, let swHeight = self.scanWindowHeightFactor {
                            let wFactor = (swWidth.isInfinite || swWidth.isNaN) ? 1.0 : max(0.0, min(1.0, swWidth))
                            let hFactor = (swHeight.isInfinite || swHeight.isNaN) ? 1.0 : max(0.0, min(1.0, swHeight))
                            let xMin = 0.5 - wFactor / 2.0
                            let xMax = 0.5 + wFactor / 2.0
                            let yMin = 0.5 - hFactor / 2.0
                            let yMax = 0.5 + hFactor / 2.0
                            
                            let sumX = screenCorners.map { Double($0.x) }.reduce(0, +)
                            let sumY = screenCorners.map { Double($0.y) }.reduce(0, +)
                            let cx = sumX / Double(screenCorners.count)
                            let cy = sumY / Double(screenCorners.count)
                            
                            let normX = cx / viewWidth
                            let normY = cy / viewHeight
                            
                            let inside = normX >= xMin && normX <= xMax && normY >= yMin && normY <= yMax
                            if !inside { continue }
                        }
                        
                        // Duplicate prevention
                        var isNewScan = true
                        if (!self.allowDuplicate) {
                            if let lastScanTime = self.scannedCache[stringValue], (currentTime - lastScanTime) < Double(self.duplicateDelay) {
                                isNewScan = false
                            }
                        }
                        
                        if !self.allowDuplicate && !isNewScan {
                            continue
                        }
                        
                        acceptedEntries.append((observation: observation, stringValue: stringValue, imageCorners: imageCorners))
                    }
                }
                
                if acceptedEntries.isEmpty {
                    self.imagesCurrentlyBeingProcessed = false
                    return
                }

                // Direct JPEG capture without Laplacian blur rejection
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
                
                let finalAcceptedEntries = acceptedEntries
                if finalAcceptedEntries.isEmpty {
                    self.imagesCurrentlyBeingProcessed = false
                    return
                }
                
                // Dispatch to main thread to perform UI-thread updates and fire eventSink safely
                DispatchQueue.main.async { [weak self] in
                    guard let self = self else { return }
                    defer {
                        self.imagesCurrentlyBeingProcessed = false
                    }
                    
                    var finalResults: [[String: Any]] = []
                    
                    for entry in finalAcceptedEntries {
                        let stringValue = entry.stringValue
                        self.scannedCache[stringValue] = currentTime
                        
                        let barcodeType = self.mapVisionSymbologyToMetadataType(entry.observation.symbology)
                        
                        var result: [String: Any] = [
                            "value": stringValue,
                            "type": barcodeType,
                            "timestamp": Int(currentTime),
                            "corners": entry.imageCorners,
                            "imageWidth": Int(imgWidth),
                            "imageHeight": Int(imgHeight),
                            "imageRejected": false
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
            
            request.symbologies = self.configuredSymbologies.isEmpty
                ? [.code128, .qr, .ean8, .ean13, .pdf417, .code39, .code93, .itf14, .dataMatrix, .aztec]
                : self.configuredSymbologies
            do {
                try requestHandler.perform([request])
            } catch {
                print("Vision perform error: \(error.localizedDescription)")
                self.imagesCurrentlyBeingProcessed = false
            }
        }
    }
    
    // Maps Dart BarcodeFormat enum names (lowercased) to VNBarcodeSymbology; unknown names are silently dropped.
    private static func symbologiesFromFormatNames(_ names: [String]) -> [VNBarcodeSymbology] {
        if names.contains(where: { $0.lowercased() == "allformats" }) { return [] }
        return names.compactMap { name -> VNBarcodeSymbology? in
            switch name.lowercased() {
            case "code128":    return .code128
            case "code39":     return .code39
            case "code93":     return .code93
            case "datamatrix": return .dataMatrix
            case "ean13":      return .ean13
            case "ean8":       return .ean8
            case "itf":        return .itf14
            case "qrcode":     return .qr
            case "pdf417":     return .pdf417
            case "aztec":      return .aztec
            default:           return nil
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
        
        let bounds = _view.bounds
        let viewWidth = Double(bounds.width)
        let viewHeight = Double(bounds.height)
        
        self.orientationLock.lock()
        self.cachedCGImageOrientation = cgOrientation
        self.cachedViewWidth = viewWidth
        self.cachedViewHeight = viewHeight
        self.orientationLock.unlock()
    }
    
    static func laplacianVariance(cgImage: CGImage) -> Double? {
        let width = cgImage.width
        let height = cgImage.height
        
        var roiWidth = width
        var roiHeight = height
        
        // 1. Draw CGImage into an 8-bit grayscale bitmap context
        let colorSpace = CGColorSpaceCreateDeviceGray()
        var pixels = [UInt8](repeating: 0, count: roiWidth * roiHeight)
        guard let context = CGContext(
            data: &pixels,
            width: roiWidth,
            height: roiHeight,
            bitsPerComponent: 8,
            bytesPerRow: roiWidth,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else { return nil }
        
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: roiWidth, height: roiHeight))
        
        // 2. Low Light / Sensor Noise Mitigation: compute mean luma first
        var lumaSum: Int64 = 0
        for p in pixels {
            lumaSum += Int64(p)
        }
        let meanLuma = Double(lumaSum) / Double(pixels.count)
        if meanLuma < 40.0 {
            print("[ScannerPlatformView] Low light detected (mean luma: \(meanLuma) < 40.0), skipping blur rejection")
            return nil
        }
        
        // 3. Max ROI Downsampling cap (62500 px ceiling)
        let maxPixelsCeiling = 62500
        while roiWidth * roiHeight > maxPixelsCeiling && roiWidth >= 4 && roiHeight >= 4 {
            let newWidth = roiWidth / 2
            let newHeight = roiHeight / 2
            var downsampled = [UInt8](repeating: 0, count: newWidth * newHeight)
            for y in 0..<newHeight {
                for x in 0..<newWidth {
                    let p00 = Int(pixels[(y * 2) * roiWidth + (x * 2)])
                    let p01 = Int(pixels[(y * 2) * roiWidth + (x * 2 + 1)])
                    let p10 = Int(pixels[(y * 2 + 1) * roiWidth + (x * 2)])
                    let p11 = Int(pixels[(y * 2 + 1) * roiWidth + (x * 2 + 1)])
                    downsampled[y * newWidth + x] = UInt8((p00 + p01 + p10 + p11) / 4)
                }
            }
            pixels = downsampled
            roiWidth = newWidth
            roiHeight = newHeight
        }
        
        // 4. Cheap 3x3 box blur (noise pre-pass)
        var blurredPixels = [UInt8](repeating: 0, count: roiWidth * roiHeight)
        for y in 0..<roiHeight {
            for x in 0..<roiWidth {
                if y == 0 || y == roiHeight - 1 || x == 0 || x == roiWidth - 1 {
                    blurredPixels[y * roiWidth + x] = pixels[y * roiWidth + x]
                } else {
                    var sum = 0
                    for ky in -1...1 {
                        for kx in -1...1 {
                            sum += Int(pixels[(y + ky) * roiWidth + (x + kx)])
                        }
                    }
                    blurredPixels[y * roiWidth + x] = UInt8(sum / 9)
                }
            }
        }
        pixels = blurredPixels
        
        // 5. Laplacian kernel [[0, 1, 0], [1, -4, 1], [0, 1, 0]]
        var sumLaplacian: Double = 0.0
        var sumLaplacianSq: Double = 0.0
        var count = 0
        
        for y in 1..<(roiHeight - 1) {
            let idx = y * roiWidth
            for x in 1..<(roiWidth - 1) {
                let center = Int(pixels[idx + x])
                let left = Int(pixels[idx + x - 1])
                let right = Int(pixels[idx + x + 1])
                let up = Int(pixels[idx - roiWidth + x])
                let down = Int(pixels[idx + roiWidth + x])
                
                let lap = Double(up + down + left + right - 4 * center)
                sumLaplacian += lap
                sumLaplacianSq += lap * lap
                count += 1
            }
        }
        
        if count == 0 { return nil }
        
        let mean = sumLaplacian / Double(count)
        let variance = (sumLaplacianSq / Double(count)) - (mean * mean)
        return variance
    }
}
