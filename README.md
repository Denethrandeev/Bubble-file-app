# Bubble File Manager

The Flutter app has an Android interface for shared-storage management and a
browser workspace for selecting files without granting access to the rest of
the device. The browser workspace displays selected file names and sizes; it
does not upload or persist file contents.

## Build the web app

Install the Flutter stable SDK, then run:

```sh
flutter pub get
flutter build web --release --base-href "/Bubble-file-app/"
```

GitHub Pages deploys `build/web` from `main` using the single
`.github/workflows/flutter-web.yml` workflow. Pushes to `main` and manual
workflow dispatches use the same concurrency group so only the latest Pages
deployment continues.

## Android

The Android entry point remains in `lib/main_android.dart`. The app uses
Android-specific storage access and native plugins, which are not available in
the browser build.
