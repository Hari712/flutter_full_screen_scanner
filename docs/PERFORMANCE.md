# Performance Guide

To maintain 60 FPS while performing continuous scanning:

## 1. Optimize `overlayBuilder`
The `overlayBuilder` function fires rapidly as the `ScannerState` updates on every frame. 
- **Do NOT** put expensive API calls or deep widget trees inside the `overlayBuilder`.
- Use `const` constructors for your UI elements wherever possible.
- If you are drawing complex bounding boxes, wrap only the bounding box painter in a `CustomPaint` and leave static elements outside of the `overlayBuilder`.

## 2. Duplicate Debouncing
Utilize the `allowDuplicate` and `duplicateDelay` parameters inside `ScannerOptions`.
If you are scanning a conveyor belt of items, the scanner might detect the same barcode 30 times a second. Setting a `duplicateDelay` of 1500ms will ensure that your Dart `onScan` callback is only triggered once every 1.5 seconds for the same barcode.

## 3. Scan Window
Reduce the `scanWindow` bounds in your `ScannerOptions`. By shrinking the region of interest, ML Kit has to process fewer pixels, drastically reducing battery drain.
