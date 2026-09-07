## 0.1.1

* Sync `KhemraScannerScreen` UI improvements from the reference example app:
  - Extracted `_buildCapturedSideThumbnail()` as a named helper method in the camera header for clarity.
  - `_buildCameraHeader()` wraps its `Stack` in a `SizedBox` to match the example layout exactly.
  - Flash icon correctly toggles between `Icons.flash_on_rounded` and `Icons.flashlight_on_rounded`.
* `ScannerToolButton.active` state now matches the `CameraTool` pattern in the example.
* `_confirm()` continues to return a typed `KhemraScanResult` (no change needed; the package API is already superior to the example's raw-map approach).

## 0.0.1

* TODO: Describe initial release.
