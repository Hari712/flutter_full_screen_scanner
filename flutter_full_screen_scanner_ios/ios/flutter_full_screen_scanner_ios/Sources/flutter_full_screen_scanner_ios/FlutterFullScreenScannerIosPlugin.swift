import Flutter
import UIKit
import Vision

public class FlutterFullScreenScannerIosPlugin: NSObject, FlutterPlugin, ScannerHostApi, FlutterStreamHandler {
  var activeScannerView: ScannerPlatformView?
  var eventSink: FlutterEventSink?

  public static func register(with registrar: FlutterPluginRegistrar) {
    let instance = FlutterFullScreenScannerIosPlugin()
    
    // Setup Pigeon Host API
    ScannerHostApiSetup.setUp(binaryMessenger: registrar.messenger(), api: instance)
    
    // Setup Event Channel
    let eventChannel = FlutterEventChannel(name: "flutter_full_screen_scanner_events", binaryMessenger: registrar.messenger())
    eventChannel.setStreamHandler(instance)
    
    // Register Platform View
    let factory = ScannerPlatformViewFactory(plugin: instance)
    registrar.register(factory, withId: "flutter_full_screen_scanner_view")
  }

  // MARK: - FlutterStreamHandler
  
  public func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
    self.eventSink = events
    return nil
  }
  
  public func onCancel(withArguments arguments: Any?) -> FlutterError? {
    self.eventSink = nil
    return nil
  }

  // MARK: - ScannerHostApi

  func pause() throws {
    activeScannerView?.pause()
  }

  func resume() throws {
    activeScannerView?.resume()
  }

  func stop() throws {
    activeScannerView?.stop()
  }

  func toggleFlash() throws -> Bool {
    return activeScannerView?.toggleFlash() ?? false
  }

  func switchCamera() throws {
    activeScannerView?.switchCamera()
  }

  func focusAt(x: Double, y: Double) throws {
    activeScannerView?.focusAt(x: x, y: y)
  }

  func scanImage(path: String, completion: @escaping (Result<[ScannerResultData?], Error>) -> Void) {
    guard let image = UIImage(contentsOfFile: path),
          let cgImage = image.cgImage else {
      completion(.failure(NSError(domain: "Scanner", code: 400, userInfo: [NSLocalizedDescriptionKey: "Invalid image path"])))
      return
    }

    let request = VNDetectBarcodesRequest { (request, error) in
      if let error = error {
        completion(.failure(error))
        return
      }

      var results: [ScannerResultData] = []
      if let barcodes = request.results as? [VNBarcodeObservation] {
        for barcode in barcodes {
          if let value = barcode.payloadStringValue {
            let corners = [
              PointData(x: Double(barcode.topLeft.x * CGFloat(image.size.width)), y: Double((1 - barcode.topLeft.y) * CGFloat(image.size.height))),
              PointData(x: Double(barcode.topRight.x * CGFloat(image.size.width)), y: Double((1 - barcode.topRight.y) * CGFloat(image.size.height))),
              PointData(x: Double(barcode.bottomRight.x * CGFloat(image.size.width)), y: Double((1 - barcode.bottomRight.y) * CGFloat(image.size.height))),
              PointData(x: Double(barcode.bottomLeft.x * CGFloat(image.size.width)), y: Double((1 - barcode.bottomLeft.y) * CGFloat(image.size.height)))
            ]
            let resultData = ScannerResultData(
              value: value,
              type: barcode.symbology.rawValue,
              imageBytes: nil,
              corners: corners,
              imageWidth: Int64(image.size.width),
              imageHeight: Int64(image.size.height),
              timestamp: Int64(Date().timeIntervalSince1970 * 1000)
            )
            results.append(resultData)
          }
        }
      }
      completion(.success(results))
    }

    let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
    DispatchQueue.global(qos: .userInitiated).async {
      do {
        try handler.perform([request])
      } catch {
        completion(.failure(error))
      }
    }
  }

  func dispose() throws {
    activeScannerView?.dispose()
    activeScannerView = nil
  }
}
