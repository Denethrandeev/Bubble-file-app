# Bubble File Manager

Bubble File Manager has two separate experiences:

- **Web** (`index.html`, `styles.css`, `app.js`): a browser-only workspace. Files
  selected or dropped into the page are stored in that browser's IndexedDB on
  that device. The web app cannot silently browse the computer or phone's
  storage, and browser data is not synchronized to Android.
- **Android** (`lib/`): a Flutter app that browses shared phone storage using
  Android permissions and native file APIs.

## Test the web app

Serve the repository root over HTTP (IndexedDB is best tested on `localhost`):

```sh
python3 -m http.server 8000
```

Open `http://localhost:8000`, create a folder, upload or drop files, and try
renaming, moving/copying, favoriting, downloading, previewing, sorting, and
switching grid/list views. Reload the page to verify the workspace persists.
Use **Trash** to restore an item or permanently delete it. Clearing the site's
browser data also clears this workspace.

## Build and install the Android app

The **Build Bubble File Manager APK** workflow runs Flutter analysis and tests,
then builds a release APK and uploads it as an artifact.

1. Open this repository's **Actions** tab.
2. Select **Build Bubble File Manager APK**, then choose **Run workflow** (or
   use the latest successful run on `main`).
3. Open the completed run and download
   `bubble-file-manager-release-apk`.
4. Extract and install the APK. Android may ask you to allow installation from
   the app used to open it.
5. Grant **Allow access to manage all files** to browse the shared-storage
   folders. If you decline, use **Pick individual files** to select files with
   Android's system picker instead; the picker grants access only to the files
   you select, without granting broad media-library access.

After granting access, try the Downloads, Documents, Pictures, Music, and Videos
shortcuts, then browse into folders and test search, sorting, rename, copy/move,
share, open/preview, and Trash. Restricted Android folders display a helpful
message and can remain unavailable. Android does not permit apps to browse
other apps' private data or protected system files. Google Play distribution
with all-files access is subject to Google's file-manager policy and approval.

To run `flutter analyze` and `flutter test` locally, install the Flutter SDK and
run `flutter pub get` first. The Android Gradle scaffold and native storage
channel are generated and configured by the workflow so the repository's web
and Flutter sources stay separate.
