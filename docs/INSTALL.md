# Getting Wickfarer on your phone

Every change merged into `main` that passes CI is published as a GitHub Release, named
`v<version>.<build>` (for example `v0.0.1.57`). The newest APK is always at:

https://github.com/oddwright/wickfarer/releases/latest/download/wickfarer.apk

The repo is private, so this link needs you signed in to GitHub (in the phone's browser, or
through Obtainium with a token, below). CI keeps the last 20 builds. They are debug builds,
meant for test phones, not for a store.

## Option A: Obtainium (updates itself)

[Obtainium](https://github.com/ImranR98/Obtainium) watches GitHub Releases and installs new
APKs for you. Set up once:

1. Install Obtainium from its GitHub releases page or F-Droid.
2. Make a GitHub token so it can see the private repo: GitHub, Settings, Developer settings,
   Fine-grained tokens, Generate new token. Repository access: only `oddwright/wickfarer`.
   Permissions: Contents, read-only. Nothing else.
3. In Obtainium: Settings, GitHub, paste the token.
4. Add app, URL `https://github.com/oddwright/wickfarer`, Add.
5. Install. From then on Obtainium shows an update after each merge, and can install it in the
   background on Android 12 and newer.

## Option B: by hand

Open the link above on the phone, download `wickfarer.apk`, open it, and allow your browser to
install apps when Android asks. A new build installs over the old one and keeps your saves.

## The signing key

Android installs an update over the old app only when both are signed with the same key. If
the key changes, Android refuses the update and you have to uninstall first, which deletes your
saves.

The key lives in the repo secrets `ANDROID_KEYSTORE_BASE64`, `ANDROID_KEYSTORE_PASSWORD` and
`ANDROID_KEY_ALIAS` (set on 2026-11-05; the alias is `emberwake`, from before the rename). The
original keystore and its password are kept off GitHub by the owner; keep a copy in a password
manager, because a lost key means every phone has to uninstall once.

Without those secrets CI falls back to a key in the Actions cache, which GitHub drops after 7
days without a build (the run warns when it makes a new one). To replace the key:

```sh
keytool -genkeypair -keystore wickfarer.keystore -alias wickfarer -keyalg RSA -keysize 2048 \
  -validity 10000 -dname "CN=Wickfarer" -storepass 'PICK-A-PASSWORD' -keypass 'PICK-A-PASSWORD'
base64 -i wickfarer.keystore | tr -d '\n' | gh secret set ANDROID_KEYSTORE_BASE64
printf %s 'PICK-A-PASSWORD' | gh secret set ANDROID_KEYSTORE_PASSWORD
gh secret set ANDROID_KEY_ALIAS -b wickfarer
```

## iPhone: TestFlight

The iOS workflow (`.github/workflows/ios.yml`) exports the Xcode project on a macOS runner,
signs it through Apple's cloud with an App Store Connect API key, and uploads it to TestFlight.
macOS minutes cost ten times Linux minutes, so it runs once a night when `main` has changed,
and whenever it is started by hand (Actions, iOS, Run workflow). PRs that touch the iOS setup
build it unsigned and upload nothing.

Once: in App Store Connect, Wickfarer, TestFlight, make an Internal Testing group with yourself
in it and turn on automatic distribution. On the phone, install TestFlight and accept the
invite. Each new
build then arrives as a TestFlight update. Internal testers (people on the Apple team) get
builds as soon as Apple finishes processing them, usually within 15 minutes.

Setup, already done on 2026-11-05:

- App Store Connect app "Wickfarer", bundle ID `com.oddwright.wickfarer`, SKU `wickfarer`.
- Repo secrets: `ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_KEY_P8` (an Admin-role API key named
  "Emberwake CI"; Admin is what cloud signing needs) and `APPLE_TEAM_ID`.
- The account holder must accept each new Apple Developer Program License Agreement, or uploads
  stop working.
