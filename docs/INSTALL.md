# Getting Emberwake on your phone

Every change merged into `main` that passes CI is published as a GitHub Release, named
`v<version>.<build>` (for example `v0.0.1.57`). The newest APK is always at:

https://github.com/oddwright/emberwake/releases/latest/download/emberwake.apk

The repo is private, so this link needs you signed in to GitHub (in the phone's browser, or
through Obtainium with a token, below). CI keeps the last 20 builds.

## Option A: Obtainium (updates itself)

[Obtainium](https://github.com/ImranR98/Obtainium) watches GitHub Releases and installs new
APKs for you. Set up once:

1. Install Obtainium from its GitHub releases page or F-Droid.
2. Make a GitHub token so it can see the private repo: GitHub, Settings, Developer settings,
   Fine-grained tokens, Generate new token. Repository access: only `oddwright/emberwake`.
   Permissions: Contents, read-only. Nothing else.
3. In Obtainium: Settings, GitHub, paste the token.
4. Add app, URL `https://github.com/oddwright/emberwake`, Add.
5. Install. From then on Obtainium shows an update after each merge, and can install it in the
   background on Android 12 and newer.

## Option B: by hand

Open the link above on the phone, download `emberwake.apk`, open it, and allow your browser to
install apps when Android asks. A new build installs over the old one and keeps your saves.

## The signing key

Android installs an update over the old app only when both are signed with the same key. If
the key changes, Android refuses the update and you have to uninstall first, which deletes your
saves.

By default CI keeps its key in the Actions cache. GitHub drops a cache entry that goes 7 days
without a build, and CI then makes a new key (the run shows a warning when it does). To make the
key permanent, store one in the repo's secrets, once:

```sh
keytool -genkeypair -keystore emberwake.keystore -alias emberwake -keyalg RSA -keysize 2048 \
  -validity 10000 -dname "CN=Emberwake" -storepass 'PICK-A-PASSWORD' -keypass 'PICK-A-PASSWORD'
base64 -w0 emberwake.keystore > emberwake.keystore.b64   # macOS: base64 -i emberwake.keystore
```

Then in GitHub, the repo's Settings, Secrets and variables, Actions, add:

| Secret | Value |
| --- | --- |
| `ANDROID_KEYSTORE_BASE64` | the contents of `emberwake.keystore.b64` |
| `ANDROID_KEYSTORE_PASSWORD` | the password you picked |
| `ANDROID_KEY_ALIAS` | `emberwake` |

Keep `emberwake.keystore` somewhere safe (a password manager), and never commit it. The first
build signed with it needs one uninstall; every build after installs over the last.

## iOS (later)

iPhones cannot install an app file from a link the way Android can. A later iOS pipeline needs:

- An Apple Developer Program membership (99 USD a year). A free Apple ID can sideload through
  Xcode or AltStore, but those installs expire after 7 days and cannot be automated.
- A macOS CI runner with Xcode, and Godot's iOS export templates.
- A distribution certificate, a provisioning profile and an App Store Connect API key, stored as
  repo secrets.
- A job that exports the Xcode project, builds and signs the IPA, and uploads it to TestFlight.
  TestFlight then plays Obtainium's role: the phone gets each new build as an update.
