# DAV Drive

An iOS app that connects to WebDAV servers (copyparty, Nextcloud, ownCloud,
Apache, nginx, NAS boxes, …) and puts them in the **Files app** under
*Locations*, through a File Provider extension. No subscriptions, no tracking.

* Add any number of servers: address, user name, password (kept in the Keychain).
* Browse, open, save, upload, rename, move and delete from Files or any app's
  document picker.
* Plain `http` and self-signed certificates are allowed for home servers
  (the latter only if you turn it on per server).

## How it works

| Target | What it is |
| --- | --- |
| `DAVCore` | WebDAV client (`PROPFIND`, `GET`, `PUT`, `MKCOL`, `DELETE`, `MOVE`) and the account store, shared by both bundles through the app group `group.io.github.crazyquark.davdrive`. |
| `DAVDrive` | The app: manage servers, test the connection, register each one as a File Provider domain. |
| `DAVDriveFileProvider` | `NSFileProviderReplicatedExtension`: items are identified by their path below the server address. |

Plain WebDAV can't report changes, so a folder is listed again whenever Files
asks for changes. Uploads send `X-OC-Mtime`, which keeps modification dates on
ownCloud/Nextcloud/copyparty. copyparty also needs it to replace a file, and
only does so for accounts with delete (`d`) permission.

## Build on Linux

Uses [xtool](https://xtool.sh) (the same setup as Signwright):

```sh
xtool dev build --ipa -c release   # → xtool/DAVDrive.ipa
```

The `.ipa` holds the app and `PlugIns/DAVDriveFileProvider.appex`. When you
sideload with a free Apple ID, the app uses two App IDs (the app and the
extension) plus an app group. SideStore/AltStore rename the app group for your
team, and the app reads the new name from `ALTAppGroups` in Info.plist.

## App Store / TestFlight

`.github/workflows/app-store.yml` builds with Xcode on a GitHub macOS runner
(the project comes from `project.yml` via XcodeGen, see
`scripts/xcode-prepare.sh`), signs with Xcode cloud signing and uploads to
TestFlight. It runs on `v*` tags or by hand from the Actions tab. Without
secrets it only checks that the app builds.

One-time setup:

1. In App Store Connect, create the app: bundle ID
   `io.github.crazyquark.davdrive`, SKU of your choice. If the bundle ID isn't
   listed yet, register it in the developer portal (Identifiers), or run the
   workflow once with secrets: automatic signing registers both bundle IDs
   and the app group.
2. Add the secrets to the repo's `app-store` environment: `ASC_KEY_ID`,
   `ASC_ISSUER_ID`, `ASC_KEY_P8` (an App Store Connect API key with the
   **Admin** role) and `APPLE_TEAM_ID`.
3. Run the workflow. Build numbers are `<CFBundleVersion>.<run number>`.
   Check processing with the *Build status* workflow.

The app and the extension share the version from `Config/App-Info.plist`.
`Config/PrivacyInfo.xcprivacy` declares no tracking, no data collection,
and the reasons for UserDefaults (app group) and file timestamp use.

## Testing the WebDAV client

`DAVCore` builds on Linux too. The client was tested against wsgidav and
copyparty: listing, unicode/`#`/`?` names, upload/overwrite, move, rename,
delete, wrong password, and a base URL inside a subfolder.

## License

MIT
