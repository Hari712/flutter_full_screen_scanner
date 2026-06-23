# Full Screen Scanner SDK

A production-ready, federated Flutter plugin for high-performance, full-screen continuous barcode and QR code scanning.

## Packages

| Package | Description |
|---|---|
| [flutter_full_screen_scanner](flutter_full_screen_scanner) | The main app-facing package containing widgets and controllers. |
| [flutter_full_screen_scanner_platform_interface](flutter_full_screen_scanner_platform_interface) | The abstract platform interfaces and event models. |
| [flutter_full_screen_scanner_android](flutter_full_screen_scanner_android) | Native CameraX and ML Kit implementation for Android. |
| [flutter_full_screen_scanner_ios](flutter_full_screen_scanner_ios) | Native AVFoundation implementation for iOS. |

## Development

This repository uses [Melos](https://melos.invertase.dev/) to manage the federated packages.

### Getting Started

```bash
# Install melos globally
dart pub global activate melos

# Bootstrap the workspace
melos bootstrap
```
