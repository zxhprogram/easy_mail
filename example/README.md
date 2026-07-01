# easy_mail_example

A desktop-first Flutter email client demonstrating the `easy_mail` package.

## Run

```bash
cd example
flutter pub get
flutter run -d windows   # or macos / linux
```

## Desktop build notes

This example uses `flutter_inappwebview` to render email HTML bodies.
On Windows, the WebView2 runtime is required. If you see a CMake warning
about `CMP0175`, the included `windows/CMakeLists.txt` already sets
`cmake_policy(SET CMP0175 OLD)` to keep `flutter_inappwebview_windows`
compatible with recent CMake versions.

## Features

- IMAP / POP3 login
- Folder and message list
- WebView-rendered HTML email detail
- Attachment download
