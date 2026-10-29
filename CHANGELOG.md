## 1.0.3

### Bug Fixes
- 📱 Added missing iOS podspec, fixing "No podspec found" CocoaPods errors
- 🛠️ Fixed iOS plugin class name in pubspec.yaml so the generated registrant compiles
- 🤖 Bumped Android `compileSdkVersion` to 36

### Changes
- 🍎 iOS now uses ExternalAccessory (MFi Bluetooth Classic) instead of CoreBluetooth (BLE).
  Apps must declare their accessory protocols under `UISupportedExternalAccessoryProtocols`
- 📡 `sendData` takes an optional `protocol` to pick the iOS accessory session to write to
- ✅ Added CI that analyzes, tests and builds the example for Android, iOS and Windows

## 1.0.2

### Bug Fixes
- 🔧 Fixed MissingPluginException errors by correcting channel name mismatches
- ✅ Updated Android, iOS, and Windows plugin implementations with proper channel names
- 🛠️ Fixed Android Bluetooth permissions in plugin manifest
- 📱 Created working example app with comprehensive Bluetooth demo
- 🔍 Fixed API usage in example to match singleton pattern
- ⚡ Improved error handling and user feedback in example app
- 🎯 Added support for Android 12+ Bluetooth permissions

## 1.0.1

### Bug Fixes
- ✅ Updated repository URLs to correct GitHub location
- ✅ Improved package metadata for pub.dev publication
- ✅ Removed unsupported web platform references
- 🔧 Updated Android package structure for better compatibility

## 1.0.0

### Features
- ✨ Initial release of Flutter Bluetooth Classic plugin
- 🔍 Device discovery and pairing
- 🔗 Connection management for Android, iOS, and Windows
- 📡 Bidirectional data transmission
- 📱 Multi-platform support (Android, iOS, Windows)
- 🔄 Real-time data streaming
- 🛡️ Robust error handling and connection management

### Platform Support
- ✅ Android: Full Bluetooth Classic support
- ✅ iOS: MFi accessory framework integration
- ✅ Windows: Native Windows Bluetooth API integration

### API
- `FlutterBluetoothClassic.instance` - Main plugin interface
- `BluetoothConnection.toAddress()` - Device connection
- Device discovery and enumeration
- Data transmission and reception
- Connection state management
