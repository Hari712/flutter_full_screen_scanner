import Flutter
import UIKit
import XCTest

@testable import flutter_full_screen_scanner_ios

class RunnerTests: XCTestCase {

  func createSyntheticImage(width: Int, height: Int, checkerboard: Bool) -> CGImage? {
      let size = width * height
      var pixels = [UInt8](repeating: 128, count: size)
      
      if checkerboard {
          for y in 0..<height {
              for x in 0..<width {
                  pixels[y * width + x] = ((x / 10) + (y / 10)) % 2 == 0 ? 255 : 0
              }
          }
      }
      
      let colorSpace = CGColorSpaceCreateDeviceGray()
      guard let provider = CGDataProvider(data: Data(pixels) as CFData) else { return nil }
      
      return CGImage(
          width: width,
          height: height,
          bitsPerComponent: 8,
          bitsPerPixel: 8,
          bytesPerRow: width,
          space: colorSpace,
          bitmapInfo: [],
          provider: provider,
          decode: nil,
          shouldInterpolate: false,
          intent: .defaultIntent
      )
  }

  func testLaplacianVarianceSharpVsBlurry() {
      guard let sharpImage = createSyntheticImage(width: 100, height: 100, checkerboard: true),
            let blurryImage = createSyntheticImage(width: 100, height: 100, checkerboard: false) else {
          XCTFail("Failed to create synthetic images")
          return
      }
      
      let sharpScore = ScannerPlatformView.laplacianVariance(cgImage: sharpImage)
      let blurryScore = ScannerPlatformView.laplacianVariance(cgImage: blurryImage)
      
      XCTAssertNotNil(sharpScore)
      XCTAssertNotNil(blurryScore)
      
      XCTAssertEqual(blurryScore!, 0.0, accuracy: 0.01)
      XCTAssertTrue(sharpScore! > blurryScore!)
  }
}
