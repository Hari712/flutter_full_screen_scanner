import Flutter
import UIKit
import AVFoundation
import Vision
import CoreMotion

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
    /// Opt-in Laplacian variance check on the captured photo, mirroring Android's rejectBlurryImages/blurThreshold.
    private var rejectBlurryImages: Bool = false
    private var blurThreshold: Double = 35.0
    private var scanWindowWidthFactor: Double? = nil
    private var scanWindowHeightFactor: Double? = nil
    /// nil = no cap; set via maxExposureDurationSeconds to trade low-light brightness for less motion blur.
    private var maxExposureDurationSeconds: Double? = nil
    /// Empty = all formats (default); non-empty = Vision restricted to only these symbologies.
    private var configuredSymbologies: [VNBarcodeSymbology] = []

    private var videoDevice: AVCaptureDevice?
    private var subjectAreaChangeObserver: NSObjectProtocol?
    private var imagesCurrentlyBeingProcessed = false
    private var scanIntervalMs: Double = 50.0
    private var lastAnalysisTimestamp: TimeInterval = 0
    private var confidenceThreshold: Double = 0.0
    private var requireConsecutiveMatches: Int = 1
    // Keyed by symbology; resets when a different value is decoded for that format or the entry goes stale.
    private var consecutiveStreaks: [VNBarcodeSymbology: (value: String, count: Int, lastSeenAt: TimeInterval)] = [:]
    
    // Cached orientation and size state
    private var cachedCGImageOrientation: CGImagePropertyOrientation = .right
    private var cachedViewWidth: Double = 0.0
    private var cachedViewHeight: Double = 0.0
    private let orientationLock = NSLock()

    // Gyroscope-derived motion signal, sampled independently of the barcode decode path.
    private let motionManager = CMMotionManager()
    private var latestRotationRate: (x: Double, y: Double, z: Double) = (0.0, 0.0, 0.0)
    private let motionLock = NSLock()

    // Pre-decode motion gate: gravity-compensated linear acceleration is a better "is the phone
    // sweeping through space" signal than rotation rate (a sweep between labels is mostly translation).
    private var linearMotionMagnitude: Double = 0.0
    private var motionGateOpen: Bool = true
    private var motionSettledSampleStreak: Int = 0
    // Calibrate on-device: log linearMotionMagnitude (units of g) while sweeping between labels vs.
    // dwelling on one, and pick a cutoff between the two clusters. Starting placeholder below.
    private let motionGateThreshold: Double = 0.15
    // Hysteresis: only reopens the gate after this many consecutive samples under threshold, so a
    // frame right at the edge of a sweep isn't analyzed while the phone is still decelerating.
    private let motionSettleSampleCount = 3

    // KVO-observed AF/AE settling state; gates photo capture only, never the barcode decode.
    private var isAdjustingFocus: Bool = false
    private var isAdjustingExposure: Bool = false
    private let focusStateLock = NSLock()
    private var focusObserversAddedTo: AVCaptureDevice?

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
            if let reject = params["rejectBlurryImages"] as? Bool {
                self.rejectBlurryImages = reject
            }
            if let threshold = params["blurThreshold"] as? Double {
                self.blurThreshold = threshold
            }
            if let swWidth = params["scanWindowWidthFactor"] as? Double {
                self.scanWindowWidthFactor = swWidth
            }
            if let swHeight = params["scanWindowHeightFactor"] as? Double {
                self.scanWindowHeightFactor = swHeight
            }
            if let maxExp = params["maxExposureDurationSeconds"] as? Double {
                self.maxExposureDurationSeconds = maxExp
            }
            if let formats = params["supportedFormats"] as? [String] {
                self.configuredSymbologies = ScannerPlatformView.symbologiesFromFormatNames(formats)
            }
            if let interval = params["scanInterval"] as? Int {
                self.scanIntervalMs = Double(interval)
            }
            if let confidence = params["confidenceThreshold"] as? Double {
                self.confidenceThreshold = confidence
            }
            if let consec = params["requireConsecutiveMatches"] as? Int {
                self.requireConsecutiveMatches = consec
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

        videoCaptureDevice.addObserver(self, forKeyPath: #keyPath(AVCaptureDevice.isAdjustingFocus), options: [.new], context: nil)
        videoCaptureDevice.addObserver(self, forKeyPath: #keyPath(AVCaptureDevice.isAdjustingExposure), options: [.new], context: nil)
        focusObserversAddedTo = videoCaptureDevice

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

        startMotionUpdates()
    }

    private func startMotionUpdates() {
        guard motionManager.isDeviceMotionAvailable else { return }
        motionManager.deviceMotionUpdateInterval = 1.0 / 60.0
        let motionQueue = OperationQueue()
        motionManager.startDeviceMotionUpdates(to: motionQueue) { [weak self] motion, error in
            guard let self = self, let motion = motion else { return }
            let rr = motion.rotationRate
            let ua = motion.userAcceleration
            let linearMagnitude = sqrt(ua.x * ua.x + ua.y * ua.y + ua.z * ua.z)

            self.motionLock.lock()
            self.latestRotationRate = (rr.x, rr.y, rr.z)
            self.linearMotionMagnitude = linearMagnitude
            if linearMagnitude > self.motionGateThreshold {
                self.motionSettledSampleStreak = 0
                self.motionGateOpen = false
            } else {
                self.motionSettledSampleStreak += 1
                if self.motionSettledSampleStreak >= self.motionSettleSampleCount {
                    self.motionGateOpen = true
                }
            }
            self.motionLock.unlock()
        }
    }

    override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey: Any]?, context: UnsafeMutableRawPointer?) {
        guard let device = object as? AVCaptureDevice else { return }
        self.focusStateLock.lock()
        if keyPath == #keyPath(AVCaptureDevice.isAdjustingFocus) {
            self.isAdjustingFocus = device.isAdjustingFocus
        } else if keyPath == #keyPath(AVCaptureDevice.isAdjustingExposure) {
            self.isAdjustingExposure = device.isAdjustingExposure
        }
        self.focusStateLock.unlock()
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        // Phone is actively sweeping through space; skip decode entirely rather than decoding a
        // frame we'd discard anyway. Independent of Step 19's focus-settling gate — both must pass.
        self.motionLock.lock()
        let motionGateOpen = self.motionGateOpen
        self.motionLock.unlock()
        if !motionGateOpen {
            return
        }

        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        let currentTime = Date().timeIntervalSince1970 * 1000
        if (currentTime - lastAnalysisTimestamp) < scanIntervalMs {
            return
        }
        lastAnalysisTimestamp = currentTime

        if imagesCurrentlyBeingProcessed {
            return
        }
        imagesCurrentlyBeingProcessed = true
        
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
                            
                            let allInside = screenCorners.allSatisfy { corner in
                                let normX = Double(corner.x) / viewWidth
                                let normY = Double(corner.y) / viewHeight
                                return normX >= xMin && normX <= xMax && normY >= yMin && normY <= yMax
                            }
                            if !allInside { continue }
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
                        
                        if self.confidenceThreshold > 0.0 && observation.confidence < Float(self.confidenceThreshold) {
                            continue
                        }
                        
                        if self.requireConsecutiveMatches > 1 && Self.isWeakChecksumSymbology(observation.symbology) {
                            let prev = self.consecutiveStreaks[observation.symbology]
                            let stale = prev != nil && (currentTime - prev!.lastSeenAt) > (self.scanIntervalMs * 3.0)
                            let newCount = (!stale && prev?.value == stringValue) ? prev!.count + 1 : 1
                            self.consecutiveStreaks[observation.symbology] = (value: stringValue, count: newCount, lastSeenAt: currentTime)
                            if newCount < self.requireConsecutiveMatches { continue }
                            self.consecutiveStreaks.removeValue(forKey: observation.symbology)
                        }
                        
                        acceptedEntries.append((observation: observation, stringValue: stringValue, imageCorners: imageCorners))
                    }
                }
                
                if acceptedEntries.isEmpty {
                    self.imagesCurrentlyBeingProcessed = false
                    return
                }

                // Crop to the union bounding box of accepted entries with 50% padding per side (generous for curved/wrapped labels).
                var imageBytes: FlutterStandardTypedData? = nil
                var cropOriginX: Double = 0.0
                var cropOriginY: Double = 0.0
                var cropWidth: Double = imgWidth
                var cropHeight: Double = imgHeight

                // AF/AE still settling (e.g. mid focus-rack on a close-macro sweep) makes for a soft/hazy photo
                // even though the decode itself (above) is unaffected; skip the JPEG for this frame only.
                self.focusStateLock.lock()
                let stillSettling = self.isAdjustingFocus || self.isAdjustingExposure
                self.focusStateLock.unlock()
                var sharpnessScore: Double? = nil
                var blurRejected = false

                if self.enableImageCapture && !stillSettling {
                    let ciContext = CIContext()
                    let ciImage = CIImage(cvPixelBuffer: pixelBuffer).oriented(cgOrientation)
                    var cMinX = imgWidth, cMaxX = 0.0, cMinY = imgHeight, cMaxY = 0.0
                    for entry in acceptedEntries {
                        for corner in entry.imageCorners {
                            let cx = corner["x"] ?? 0.0, cy = corner["y"] ?? 0.0
                            if cx < cMinX { cMinX = cx }; if cx > cMaxX { cMaxX = cx }
                            if cy < cMinY { cMinY = cy }; if cy > cMaxY { cMaxY = cy }
                        }
                    }
                    let barcodeW = cMaxX - cMinX, barcodeH = cMaxY - cMinY
                    if barcodeW > 0 && barcodeH > 0 {
                        let padX = Swift.max(barcodeW * 0.80, imgWidth * 0.15, 60.0)
                        let minDesiredHeight = Swift.max(barcodeW * 1.20, imgHeight * 0.35)
                        let totalHeightWithPad = Swift.max(barcodeH + barcodeH * 3.0, minDesiredHeight)
                        let padY = Swift.max((totalHeightWithPad - barcodeH) / 2.0, 60.0)
                        cropOriginX = Swift.max(0.0, cMinX - padX)
                        cropOriginY = Swift.max(0.0, cMinY - padY)
                        cropWidth  = Swift.min(imgWidth,  cMaxX + padX) - cropOriginX
                        cropHeight = Swift.min(imgHeight, cMaxY + padY) - cropOriginY
                    }
                    // CIImage Y increases upward; convert UIKit crop rect (Y downward) to CIImage space.
                    let ciCropRect = CGRect(x: cropOriginX, y: imgHeight - cropOriginY - cropHeight,
                                           width: cropWidth, height: cropHeight)
                    if let cgImage = ciContext.createCGImage(ciImage, from: ciCropRect) {
                        // Opt-in Laplacian check on the bitmap; gates JPEG compression so rejected frames skip that CPU cost too.
                        if self.rejectBlurryImages {
                            let variance = self.computeLaplacianVariance(cgImage: cgImage)
                            sharpnessScore = variance
                            if let variance = variance, variance < self.blurThreshold {
                                blurRejected = true
                            }
                        }
                        if !blurRejected {
                            let uiImage = UIImage(cgImage: cgImage)
                            if let jpegData = uiImage.jpegData(compressionQuality: 0.8) {
                                imageBytes = FlutterStandardTypedData(bytes: jpegData)
                            }
                        }
                    }
                }

                let imageRejected = stillSettling || blurRejected
                let imageRejectReason: String? = stillSettling ? "focusSettling" : (blurRejected ? "blurry" : nil)

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

                    // Near-zero-cost motion signal, independent of the Vision decode gate above; the app layer decides what to do with it.
                    self.motionLock.lock()
                    let rotationRate = self.latestRotationRate
                    self.motionLock.unlock()
                    let gyroMagnitude = sqrt(rotationRate.x * rotationRate.x + rotationRate.y * rotationRate.y + rotationRate.z * rotationRate.z)
                    let exposureSeconds = self.videoDevice?.exposureDuration.seconds ?? 0.0
                    let motionBlurRisk = gyroMagnitude * exposureSeconds

                    for entry in finalAcceptedEntries {
                        let stringValue = entry.stringValue
                        self.scannedCache[stringValue] = currentTime
                        
                        let barcodeType = self.mapVisionSymbologyToMetadataType(entry.observation.symbology)
                        
                        let adjustedCorners = entry.imageCorners.map { c -> [String: Double] in
                            ["x": (c["x"] ?? 0.0) - cropOriginX, "y": (c["y"] ?? 0.0) - cropOriginY]
                        }
                        var result: [String: Any] = [
                            "value": stringValue,
                            "type": barcodeType,
                            "timestamp": Int(currentTime),
                            "corners": adjustedCorners,
                            "imageWidth": Int(cropWidth),
                            "imageHeight": Int(cropHeight),
                            "imageRejected": imageRejected,
                            "motionRisk": motionBlurRisk,
                            "motionBlurRisk": motionBlurRisk
                        ]

                        if let reason = imageRejectReason {
                            result["imageRejectReason"] = reason
                        }

                        if let score = sharpnessScore {
                            result["sharpnessScore"] = score
                        }

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
    
    // Opt-in sharpness check on the cropped photo, mirroring Android's computeLaplacianVarianceFromBitmap:
    // downsample -> low-light gate -> Laplacian response variance. Only called when rejectBlurryImages is true.
    private func computeLaplacianVariance(cgImage: CGImage) -> Double? {
        let srcWidth = cgImage.width
        let srcHeight = cgImage.height
        guard srcWidth > 2, srcHeight > 2 else { return nil }

        // Downsample cap mirrors Android's ~62500px ceiling; CG's interpolated draw also acts as a cheap noise pre-pass.
        let maxDimension = 250
        let scale = min(1.0, Double(maxDimension) / Double(max(srcWidth, srcHeight)))
        let width = max(4, Int(Double(srcWidth) * scale))
        let height = max(4, Int(Double(srcHeight) * scale))

        let colorSpace = CGColorSpaceCreateDeviceGray()
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else { return nil }
        context.interpolationQuality = .high
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        guard let data = context.data else { return nil }
        let pixels = data.bindMemory(to: UInt8.self, capacity: width * height)

        // Low-light gate: Laplacian variance naturally collapses under noise suppression in dim light,
        // which would otherwise cause false blur rejections.
        var lumaSum = 0
        for i in 0..<(width * height) {
            lumaSum += Int(pixels[i])
        }
        let meanLuma = Double(lumaSum) / Double(width * height)
        if meanLuma < 40.0 {
            return nil
        }

        var sumLaplacian = 0.0
        var sumLaplacianSq = 0.0
        var count = 0
        for y in 1..<(height - 1) {
            let rowIdx = y * width
            for x in 1..<(width - 1) {
                let center = Double(pixels[rowIdx + x])
                let left = Double(pixels[rowIdx + x - 1])
                let right = Double(pixels[rowIdx + x + 1])
                let up = Double(pixels[rowIdx - width + x])
                let down = Double(pixels[rowIdx + width + x])
                let lap = up + down + left + right - 4 * center
                sumLaplacian += lap
                sumLaplacianSq += lap * lap
                count += 1
            }
        }
        guard count > 0 else { return nil }
        let mean = sumLaplacian / Double(count)
        return (sumLaplacianSq / Double(count)) - (mean * mean)
    }

    // Code 39, ITF-14, and Codabar lack strong checksums; all other Vision symbologies are excluded from this gate.
    private static func isWeakChecksumSymbology(_ symbology: VNBarcodeSymbology) -> Bool {
        if #available(iOS 15.0, *) {
            if symbology == .codabar { return true }
        }
        return symbology == .code39 || symbology == .itf14
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
        motionManager.stopDeviceMotionUpdates()
        if let device = focusObserversAddedTo {
            device.removeObserver(self, forKeyPath: #keyPath(AVCaptureDevice.isAdjustingFocus))
            device.removeObserver(self, forKeyPath: #keyPath(AVCaptureDevice.isAdjustingExposure))
            focusObserversAddedTo = nil
        }
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

    deinit {
        if let device = focusObserversAddedTo {
            device.removeObserver(self, forKeyPath: #keyPath(AVCaptureDevice.isAdjustingFocus))
            device.removeObserver(self, forKeyPath: #keyPath(AVCaptureDevice.isAdjustingExposure))
        }
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
}
