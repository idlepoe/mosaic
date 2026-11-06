# Physical-device test report

Date: **November 6, 2026 (Asia/Seoul)**  
Device: **Samsung SM-S931N**, Android API **36**  
Interaction: **scrcpy** mirrored on Windows, operated through computer-use  
Application: **Mosaic Android 1.0.0+1**, installed ARM64 release-mode APK with development signing

## Input and configuration

Input: `mosaic_port_sample.mp4`, copied from the original Mosaic repository's `src-tauri/tests/fixtures/sample.mp4`. This is a small H.264 color-bar test fixture (320 × 240, approximately two seconds), not a personal video.

- Grid: 3 columns × 3 rows
- Requested output width: 1280 px
- Gap: 8 px
- Screenshot / preview segment count: 6
- Requested segment length: 2 seconds, bounded to the input duration
- Animation rate: 8 FPS
- Image quality: 85
- Timestamps and metadata header enabled, dark output background
- Static format: JPEG; animation format: WebP
- All four output types selected

## Manual checks through scrcpy

| Check | Result | Evidence |
|---|---|---|
| Find and select the test file in Android's system picker | Passed | Queue screenshot 01 |
| Change grid rows from 4 to 3 | Passed | Settings screenshot 02 |
| Select all four output types | Passed | Screenshot 03 |
| Start generation and observe progress | Passed | Screenshot 04 |
| Complete the batch without a per-file error | Passed | Screenshot 05 |
| View animated sheet and preview reel | Passed | Screenshots 06–07; frame changes observed in scrcpy |
| View timestamped individual screenshots | Passed | Screenshot 08 |
| View and enlarge the static contact sheet | Passed | Screenshots 09–10 |
| Open the FFprobe metadata dialog | Passed | Screenshot 11 |
| Export the animated sheet using Android's Save document dialog | Passed | File exists in the device Download directory and was pulled into this project |
| Terminate and relaunch the app, then reopen Results | Passed | Screenshot 12 |
| Retain output-type settings after restart | Passed | All four output selections remained checked |

Nine outputs were generated: a JPEG contact sheet, six JPEG screenshots, a WebP preview reel, and a WebP animated sheet. The source queue is intentionally transient and was empty after restarting; completed results remained available.

## Export evidence

- Device destination: `Download/mosaic_port_sample_animated_sheet.webp`
- Project copy: [mosaic_port_sample_animated_sheet.webp](test-results/mosaic_port_sample_animated_sheet.webp)
- Size: **446,896 bytes**
- SHA-256: `EBF6ECE9CD3518F7D43DC5E4E9E319627547DF5AB5E77C6EEE6136B3506764FA`

No Android file-dialog screenshots were retained because those dialogs also displayed unrelated personal files. App screenshots contain the synthetic test input and its generated results.

## Earlier automated checks in this implementation session

- `flutter analyze`: no issues found
- `flutter test`: 4 tests passed
- Native integration test on this physical device: passed
- Native checks covered four pipelines, JPEG/PNG/WebP/GIF/WebM, output collisions, cancellation, and a subsequent fresh operation
- Debug APK build: passed
- ARM64 release-mode APK build: passed; installation and launch on the physical device succeeded

The manual scrcpy session did not rerun every automated encoding format. It used JPEG and WebP outputs.

## Signed release build validation

After the manual UI test, version `1.0.0+2` was built using the external release keystore referenced by the local, Git-ignored `android/key.properties`. The signing setup follows the existing `gps_gallery` project. No key file or signing password is committed or attached to GitHub Releases.

- ARM64 release APK build: passed
- `apksigner verify`: passed, APK Signature Scheme v2
- APK certificate fingerprint compared against Gradle's release signing report: matched
- Package: `com.mosaicvideo.mosaic`, version name `1.0.0`
- ARM64 split APK version code: `2002` (ABI offset plus Flutter build number 2)
- Signer certificate SHA-256: `FFE4A47D5541C2705AEE3EBD333EE9A605B4581B39C05631EBA5790419415B41`

The release-signed APK was not installed over the earlier development-signed app because the signing identities differ. No app data was removed. The UI and native pipeline code are unchanged from the physically tested build.

## Manual checks not performed

- Sending a file to an external share recipient; no content was sent
- Deleting results through the UI
- Long videos, very large source files, or a multi-video batch
- HDR10/HLG conversion, Dolby Vision rejection, or unusual codecs/containers
- Background interruption, screen rotation, accessibility, or broad device compatibility
- Production signing or store publication

These checks are not claimed as passed. The screenshot gallery and this report document the tested scope only.
