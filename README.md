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

## Testing the WebDAV client

`DAVCore` builds on Linux too. The client was tested against wsgidav and
copyparty: listing, unicode/`#`/`?` names, upload/overwrite, move, rename,
delete, wrong password, and a base URL inside a subfolder.

## License

MIT
