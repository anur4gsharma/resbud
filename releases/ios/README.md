# Resbud — iOS Export & Deployment Guide

This directory contains the export configuration, build scripts, and release metadata for the iOS client of Resbud.

---

## 1. Automated GitHub Actions CI/CD Export

Because native iOS compiling and code signing requires Apple macOS and Xcode toolchains, Resbud includes an automated CI/CD export pipeline configured in [`.github/workflows/build-ios.yml`](file:///home/anur4gsharma/college/CP/FODS/.github/workflows/build-ios.yml).

### Automatic Triggers:
- Every push to `main` modifying mobile code.
- Manual trigger via **GitHub Actions** > **Build & Export iOS App** > **Run workflow**.

### Output Artifacts Produced:
1. `Resbud-ios-unsigned.ipa`: Installable unsigned iOS Application Package.
2. `Resbud-Runner.xcarchive.zip`: Full Xcode archive ready for Xcode Organizer, TestFlight, or App Store submission.

---

## 2. Local Build on macOS (Xcode)

If you have a Mac or macOS build machine with Xcode and Flutter installed:

```bash
# 1. Navigate to mobile workspace
cd mobile

# 2. Fetch Flutter and CocoaPods dependencies
flutter pub get
cd ios && pod install && cd ..

# 3. Build unsigned IPA
flutter build ipa --no-codesign --dart-define=RESBUD_API_BASE_URL=https://resbud-api.onrender.com

# 4. Or build signed IPA with your Apple Developer Team
flutter build ipa --export-method=app-store --dart-define=RESBUD_API_BASE_URL=https://resbud-api.onrender.com
```

Output location:
`mobile/build/ios/archive/Runner.xcarchive`
`mobile/build/ios/ipa/*.ipa`

---

## 3. Sideloading the Unsigned IPA onto iPhone / iPad

To install the exported `Resbud-ios-unsigned.ipa` onto a physical iOS device without an Apple Developer enterprise account:

### Option A: Sideloadly (macOS / Windows)
1. Download [Sideloadly](https://sideloadly.io/).
2. Connect your iPhone via USB.
3. Drag `Resbud-ios-unsigned.ipa` into Sideloadly.
4. Enter your personal Apple ID (free 7-day developer certificate).
5. Click **Start**. The app will appear on your Home Screen.
6. On iPhone, navigate to **Settings > General > VPN & Device Management** and trust your Apple ID profile.

### Option B: AltStore
1. Install [AltServer](https://altstore.io/) on your computer.
2. Send `Resbud-ios-unsigned.ipa` to your iPhone (via AirDrop or iCloud Drive).
3. Open the file in **AltStore** to sign and install it.

---

## 4. App Permissions & Capabilities Configured

The iOS Runner is pre-configured in [`mobile/ios/Runner/Info.plist`](file:///home/anur4gsharma/college/CP/FODS/mobile/ios/Runner/Info.plist) with:
- **Display Name**: `Resbud`
- **Photo Library Access**: `NSPhotoLibraryUsageDescription` configured for attaching research plots and figures.
- **Document & File Sharing**: `UIFileSharingEnabled` and `LSSupportsOpeningDocumentsInPlace` enabled so exported DOCX and PDF manuscripts are directly accessible in the iOS **Files** app.
- **Minimum iOS Target**: iOS 13.0+.
