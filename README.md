# Syncthing iOS

Native SwiftUI client shell for Syncthing, based on the REST API patterns used by
the Android wrapper in `../syncthing-android` and the upstream Syncthing REST
surface in `../syncthing`.

## Current Scope

- Configure a Syncthing GUI/API endpoint and API key.
- Fetch `/rest/system/status`, `/rest/system/version`, `/rest/config`,
  and `/rest/system/connections`.
- Show local device status, folders, remote devices, and connection state.
- Open the Syncthing Web GUI from inside the app.

This iteration is usable as a controller for an existing Syncthing instance. It
does not embed or run the Go Syncthing core on iOS yet. That work requires a
separate iOS build strategy, entitlement review, background execution policy, and
filesystem access design.

## Use

1. Open Syncthing's Web GUI on the node you want to control.
2. Copy the API key from Actions > Settings > GUI.
3. In the iOS app, open Settings.
4. Enter the GUI address, for example `http://127.0.0.1:8384` for a local
   simulator setup or `https://host.example.com` for a remote HTTPS endpoint.
5. Enter the API key and tap Save & Connect.

The API key is stored in Keychain. HTTP is only allowed for local networking by
default; use HTTPS for remote Syncthing endpoints.

## Build

Open `SyncthingiOS.xcodeproj` in Xcode and run the `SyncthingiOS` target on an
iOS simulator or device.

The app uses only Apple frameworks: SwiftUI, Combine, Foundation, and WebKit.
