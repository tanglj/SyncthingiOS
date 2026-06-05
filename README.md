# Syncthing iOS

Native SwiftUI client shell for Syncthing, based on the REST API patterns used by
the Android wrapper in `../syncthing-android` and the upstream Syncthing REST
surface in `../syncthing`.

## Current Scope

- Run an embedded Syncthing core while the iOS app is in the foreground.
- Use the app-owned local Syncthing GUI/API endpoint at
  `http://127.0.0.1:8384`.
- Fetch `/rest/system/status`, `/rest/system/version`, `/rest/config`,
  and `/rest/system/connections`.
- Show local device status, folders, remote devices, and connection state.
- Open the Syncthing Web GUI from inside the app.
- Configure an external Syncthing GUI/API endpoint and API key when needed.

Background synchronization, Files app integration, and App Store entitlement
review are intentionally out of scope for this foreground build.

## Use

1. Open Syncthing's Web GUI on the node you want to control.
2. Copy the API key from Actions > Settings > GUI.
3. In the iOS app, open Settings.
4. Enter the GUI address, for example `http://127.0.0.1:8384` for a local
   simulator setup or `https://host.example.com` for a remote HTTPS endpoint.
5. Enter the API key and tap Save & Connect.

The API key is stored in Keychain. HTTP is only allowed for local networking by
default; use HTTPS for remote Syncthing endpoints.

## Embedded Core

The foreground build uses:

- Swift lifecycle owner: `SyncthingCoreManager`
- Go adapter: `../syncthing/mobile/ioscore`
- Local API key: `ios-local-syncthing-core`
- Data home: app Application Support, under `SyncthingCore`

Generate the iOS framework after Go dependencies are available:

```bash
Scripts/build-ios-core.sh
```

The script writes `SyncthingiOS/Frameworks/Ioscore.xcframework`. Rebuild the app
after regenerating the framework. Without the framework, the app still builds
and shows a clear "Core not bundled" status.

On launch, the app starts the core and waits for `/rest/system/ping` through the
embedded adapter before showing "Core running".

## Verification

Current verification commands:

```bash
xcodebuild -project SyncthingiOS.xcodeproj -scheme SyncthingiOS \
  -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath .derivedData CODE_SIGNING_ALLOWED=NO build

xcodebuild -project SyncthingiOS.xcodeproj -scheme SyncthingiOS \
  -destination 'platform=iOS,name=<设备名称>' \
  -derivedDataPath .derivedData-device -allowProvisioningUpdates \
  DEVELOPMENT_TEAM=<你的 Apple Team ID> build
```

The foreground build has also been installed on `<设备名称>`. If iOS blocks the
first launch, trust the developer profile in Settings > General > VPN & Device
Management.

## Build

Open `SyncthingiOS.xcodeproj` in Xcode and run the `SyncthingiOS` target on an
iOS simulator or device.

The app uses only Apple frameworks: SwiftUI, Combine, Foundation, and WebKit.
