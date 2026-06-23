import Flutter
import UIKit

class ScannerPlatformViewFactory: NSObject, FlutterPlatformViewFactory {
    private var plugin: FlutterFullScreenScannerIosPlugin

    init(plugin: FlutterFullScreenScannerIosPlugin) {
        self.plugin = plugin
        super.init()
    }

    func create(
        withFrame frame: CGRect,
        viewIdentifier viewId: Int64,
        arguments args: Any?
    ) -> FlutterPlatformView {
        let view = ScannerPlatformView(
            frame: frame,
            viewIdentifier: viewId,
            arguments: args,
            plugin: plugin
        )
        plugin.activeScannerView = view
        return view
    }

    func createArgsCodec() -> FlutterMessageCodec & NSObjectProtocol {
        return FlutterStandardMessageCodec.sharedInstance()
    }
}
