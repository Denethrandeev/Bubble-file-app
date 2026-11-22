# Bubble File Manager

Bubble File Manager has two separate experiences:

- **Web** (`index.html`, `styles.css`, `app.js`): a browser-only workspace. Files
  selected or dropped into the page are stored in that browser's IndexedDB on
  that device. The web app cannot silently browse the computer or phone's
  storage, and browser data is not synchronized to Android.
- **Android** (`lib/`): a Flutter app that browses shared phone storage using
  Android permissions and native file APIs.

## Run and build the web app

The web app is static HTML, CSS, and JavaScript; there is no compilation step.
Serve the repository root over HTTP (IndexedDB is best tested on `localhost`):

```sh
python3 -m http.server 8000
```

Open `http://localhost:8000`, create a folder, upload or drop files, and try
renaming, moving/copying, favoriting, downloading, previewing, sorting, and
switching grid/list views. Workspace items and file contents are saved in
IndexedDB for this site in the current browser profile. Reload the page to
verify the workspace persists.
Use **Trash** to restore an item or permanently delete it. Clearing the site's
browser data also clears this workspace.

To publish the web app, deploy the repository root as static files (for example,
the existing GitHub Pages workflow does this on pushes to `main`).

## Build and install the Android APK

The **Build Bubble File Manager APK** workflow generates the Android platform
scaffold and native storage channel, verifies the storage workflow, runs Flutter
analysis and tests, then builds a release APK and uploads it as an artifact.
The repository does not include generated Android Gradle files; use this
workflow for a reproducible APK build.

1. Open this repository's **Actions** tab.
2. Select **Build Bubble File Manager APK**, then choose **Run workflow** (or
   use the latest successful run on `main`).
3. Open the completed run and download
   `bubble-file-manager-release-apk`.
4. Extract and install the APK. Android may ask you to allow installation from
   the app used to open it.
5. Grant **Allow access to manage all files** to browse shared-storage folders.
   If you decline, use **Pick individual files** on the storage prompt to open
   Android's system picker; selected files remain available to open or share
   without granting broad storage access.

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
