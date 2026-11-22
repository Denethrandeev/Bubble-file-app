# Bubble File Manager

Bubble File Manager is a Flutter Android app for browsing and organizing files
in a phone's shared storage. It includes the web preview at the repository root
and a Flutter app in `lib/`.

## Install the Android app

The Android build runs in GitHub Actions:

1. Open this repository's **Actions** tab.
2. Select **Build Bubble File Manager APK** and choose **Run workflow**.
3. When the run completes, open it and download the
   `bubble-file-manager-release-apk` artifact.
4. Extract the APK and install it on your Android phone. Android may ask you to
   allow installation from the browser or file manager used to open it.
5. On first launch, tap **Allow storage access** and enable **Allow access to
   manage all files** in Android settings. Return to the app to browse storage.

The app can browse user-accessible shared storage, including common folders such
as Downloads, Documents, Pictures, Music, and Videos. Android does not allow
apps to browse private data belonging to other apps or protected system files.
Some protected Android folders (including `Android/data` and `Android/obb`) may
also remain unavailable. Access to all files is a special Android permission;
publishing an app that requests it on Google Play is subject to Google's
file-manager policy and approval.

To run the Flutter app locally, install Flutter and Android Studio, then run:

```sh
flutter create --platforms=android --org com.aqua --project-name bubble_file_manager .
flutter pub get
flutter run
```