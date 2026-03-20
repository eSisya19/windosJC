# WebShell Flutter App
A Flutter Android shell that opens a URL in a WebView with full **download** and **upload** support.

---

## 🔧 Quick Setup

### 1. Install Flutter
If you haven't already:
- Download Flutter SDK: https://docs.flutter.dev/get-started/install
- Add to PATH and run `flutter doctor` to verify

### 2. Set Your URL
Open `lib/main.dart` and change line 14:
```dart
const String kStartUrl = 'https://your-website.com';
```

### 3. (Optional) Change App Name & Package ID
- **App name** → `android/app/src/main/AndroidManifest.xml` → `android:label="WebShell"`
- **Package ID** → `android/app/build.gradle` → `applicationId "com.example.webshell"`
- **MainActivity** → rename folder `kotlin/com/example/webshell/` to match your package

### 4. Install Dependencies
```bash
cd webshell_app
flutter pub get
```

### 5. Build the APK
```bash
# Debug APK (for testing)
flutter build apk --debug

# Release APK (for distribution)
flutter build apk --release

# Split APKs by ABI (smaller file sizes)
flutter build apk --split-per-abi
```

APK output: `build/app/outputs/flutter-apk/`

---

## 📱 Features

| Feature | Support |
|---|---|
| Open URL in WebView | ✅ |
| File Upload (`<input type="file">`) | ✅ |
| File Download (any file type) | ✅ |
| Download progress indicator | ✅ |
| Open downloaded file | ✅ |
| Page loading indicator | ✅ |
| JavaScript enabled | ✅ |
| All navigation allowed | ✅ |

---

## 🔑 Permissions Explained

| Permission | Why |
|---|---|
| `INTERNET` | Load the URL |
| `READ_EXTERNAL_STORAGE` | Pick files to upload (Android ≤12) |
| `WRITE_EXTERNAL_STORAGE` | Save downloads (Android ≤9) |
| `READ_MEDIA_*` | Pick files to upload (Android 13+) |
| `MANAGE_EXTERNAL_STORAGE` | Save to Downloads folder |

---

## 🛠 Troubleshooting

### Downloads not working
- Make sure the URL returns proper `Content-Disposition` headers
- Grant storage permissions when prompted on device

### Uploads not triggering file picker
- Ensure `<input type="file">` is used on the website
- Test on a real device (emulator may have issues with file picker)

### Build errors
```bash
flutter clean
flutter pub get
flutter build apk
```

### `minSdkVersion` error
In `android/app/build.gradle`, ensure `minSdk 21` or higher.

---

## 📦 Dependencies

| Package | Purpose |
|---|---|
| `webview_flutter` | Core WebView |
| `webview_flutter_android` | Android file upload via `setOnShowFileSelector` |
| `file_picker` | Native file picker for uploads |
| `permission_handler` | Request storage permissions |
| `http` | Stream file downloads with progress |
| `path_provider` | Get Downloads directory path |
| `open_file` | Open downloaded files |
