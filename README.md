# Via for Android and Windows

A Flutter client for [Via](../Via), the self-hosted way to send links, text and files between
your devices.

- **Receive**: links open in the browser, text is copied to the clipboard, and files are saved
  to Downloads (`Download/Via` on Android). Every item shows a notification and is kept in a
  local history.
- **Send**: send a link, one or more files, or some text to any of your devices and contacts.
- **Share target (Android)**: share anything to Via and a popup over the current app asks
  which devices to send it to. Links, text and files are told apart automatically.

## Setup

On first start the app asks for your server's address, then your username, password and a
name for this device. The password is only used to register the device: the app keeps the
device token (in the Android Keystore / Windows Credential Manager), never the password or a
session. The device can be renamed later in *Settings*.

## Building

Flutter 3.41+ (Dart 3.11+).

```sh
flutter pub get
flutter run -d windows
flutter run -d <android device>

flutter build windows --release       # build/windows/x64/runner/Release/
flutter build apk --release           # build/app/outputs/flutter-apk/app-release.apk
```

Android needs Android 10 (API 29) or newer.

### Signing (Android)

Release APKs are signed with the key given by `VIA_KEYSTORE_FILE`, `VIA_KEYSTORE_PASSWORD`,
`VIA_KEY_ALIAS` and `VIA_KEY_PASSWORD`, or by `android/key.properties` (git-ignored; keys
`storeFile`, `storePassword`, `keyAlias`, `keyPassword`). Without either, they fall back to the
debug key, which is fine for testing but can't update a properly signed install. Create a key
once and keep it safe; every future update must be signed with it:

```sh
keytool -genkeypair -keystore via-release.jks -alias via -keyalg RSA -keysize 4096 -validity 10000
```

### Windows installer

`windows/installer/via.iss` is an [Inno Setup](https://jrsoftware.org/isinfo.php) script. It
installs per user (no admin prompt) into `%LOCALAPPDATA%\Programs\Via`, with an optional "start
when I sign in" entry, and closes a running Via before upgrading or uninstalling.

```sh
flutter build windows --release
iscc /DAppVersion=1.2.3 windows/installer/via.iss    # build/installer/Via-1.2.3-windows-setup.exe
```

## Releases

Publishing a GitHub release runs `.github/workflows/release.yml`. It runs the analyzer and
tests, then builds and attaches `Via-<version>-windows-setup.exe` and
`Via-<version>-android.apk`. The tag is the version (`v1.2.3`); the Android `versionCode` is
derived from it, so versions must only go up. It can also be re-run for an existing tag from
the Actions tab.

Repository secrets:

| Secret | |
|---|---|
| `ANDROID_KEYSTORE_BASE64` | `base64 -w0 via-release.jks` |
| `ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEY_ALIAS`, `ANDROID_KEY_PASSWORD` | for that keystore |
| `GOOGLE_SERVICES_JSON` | optional: contents of the Firebase `google-services.json` (FCM wake-ups) |

Without the keystore secrets the APK is signed with a throwaway debug key and the run shows a
warning.

### FCM wake-ups (optional)

Android receives instantly through FCM when the app is built with a Firebase project: put that
project's `google-services.json` in `android/app/` and run the
[Via FCM relay](../ViaFCMRelay) with the same project's service account. The app registers its
FCM token with the server (`PUT /v1/devices/me/push`) when the server has
`features.fcm_relay`. Without `google-services.json` the app still builds and works; it then
receives live while open and every ~15 minutes in the background.

The application id is `com.kamofa.via`. If you change it, register the new id in Firebase too.

## How it works

The app follows Via's [client guide](../Via/docs/clients.md):

- It registers as a device of type `android` or `desktop` and stores only its device token. A
  `401` signs it out.
- While running (always on Windows, in the foreground on Android) it keeps
  `GET /v1/inbox/events` open and syncs on `ready` and `push`, reconnecting with backoff and
  treating 60 s of silence as a dead connection.
- On Android, an FCM wake (`WakeService`) enqueues an expedited `WakeWorker`, which runs one
  sync in a headless Flutter engine (`wakeMain`). A periodic WorkManager task is the fallback.
- Items are acked only once handled, and handling is idempotent on the item id. Files download
  with `Range` resume and are checked against their SHA-256 before being saved. A download
  that fails 3 times waits for *Retry* in the history.
- Only `https` links from your own devices open automatically. Links from contacts, plain
  `http` links, and links that arrive while the Android app is in the background wait for a
  tap on the notification. Text from contacts isn't copied automatically.
- File names are sanitized before saving.

On Windows the app lives in the tray: closing the window hides it, *Quit* is in the tray menu,
and *Settings → Start with Windows* launches it hidden at login. A second launch shows the
running window.

### Layout

| Path | |
|---|---|
| `lib/src/api.dart` | HTTP client for the Via API |
| `lib/src/receiver.dart` | Inbox sync and handling of received items |
| `lib/src/live.dart` | SSE connection, Android background scheduling and FCM registration |
| `lib/src/history.dart` | Local history (a JSON file) and handled ids |
| `lib/src/desktop.dart` | Windows tray, window and autostart |
| `lib/ui/` | Onboarding, send, history, settings and the share popup |
| `packages/via_native/` | Android plugin: clipboard, MediaStore Downloads, share intents (works in background engines) |
| `android/app/src/main/kotlin/` | `ShareActivity`, FCM `WakeService` and `WakeWorker` |
| `scripts/update_icons.py` | Copies the icons from `../Via/branding` (`python scripts/update_icons.py`) |

## Tests

```sh
flutter test
```

The API tests run against a real server when `VIA_TEST_SERVER` is set:

```sh
# in ../Via
VIA_DATA_DIR=/tmp/via VIA_PORT=8766 VIA_ADMIN_USERNAME=alice VIA_ADMIN_PASSWORD=password123 uv run via serve
# here
VIA_TEST_SERVER=http://localhost:8766 flutter test
```
