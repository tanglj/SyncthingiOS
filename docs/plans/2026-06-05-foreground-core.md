# Foreground Embedded Core

## Goal

Build the first iOS version that can run its own Syncthing node while the app is
in the foreground.

## Architecture

The app uses a local REST API boundary:

- Go adapter: `../syncthing/mobile/ioscore`
- Swift lifecycle owner: `SyncthingCoreManager`
- Local GUI/API: `http://127.0.0.1:8384`
- Local API key: `ios-local-syncthing-core`
- Data home: app Application Support, under `SyncthingCore`

This keeps the existing dashboard, settings, and Web GUI code useful while the
core moves from an external Mac service into the app sandbox.

## Decisions

Use an in-process Go framework instead of launching a bundled executable.
iOS does not support desktop-style process management for normal apps, while a
gomobile framework can be started from Swift and tied to the app foreground
lifecycle.

Keep background sync out of this version. Foreground sync is enough to validate
configuration, device pairing, local folders, REST control, and Web GUI access.

## Runtime Behavior

`Ioscore.xcframework` has been generated and linked into the app target. The
Swift app still builds without it and reports "Core not bundled" so the UI
remains testable during local development.

The app starts core when the scene becomes active. It stops core when the scene
enters the background. The startup path waits for the embedded `Ping()` bridge to
confirm the local REST API before showing "Core running".

## Verified

- `Scripts/build-ios-core.sh` generates `Ioscore.xcframework`.
- Simulator build passes.
- iPhone build passes with bundle ID `me.tanglj.SyncthingiOS`.
- The app installs on `<设备名称>`.
- First launch may require trusting the developer profile in iOS Settings.

## Next Steps

1. Add folder creation for an app-local sync directory.
2. Add first-run pairing guidance and a local device ID display.
3. Decide whether to keep committing the generated framework or move it to a
   reproducible release artifact.
