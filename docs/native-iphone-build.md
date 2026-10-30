# A native iPhone build against the persistent environment

**Status (2026-10-27): done once, by the owner, on one iPhone, against the persistent proof of concept
(`docs/persistent-environment.md`, ADR-078, jlogicsoftware/prudent#155).** This is the procedure that
worked, what it showed, and — as plainly — what it did not. It holds **no environment fact** (ADR-021):
`SERVICE_URL`, `GCP_PROJECT`, `GCP_REGION`, `SERVICE_NAME`, `DEVICE_ID` and `TEAM_ID` below are
placeholders, and the real values live in the cloud, in Xcode and on the phone.

## What a native build is here

The client's configuration is compile-time (`ZEN_ENV`, `ZEN_PLATFORM`, `ZEN_API_URL`,
`ZEN_AUTH_REDIRECT_URI`). A build for a phone therefore **contains the server's origin**: there is no
setting to change afterwards, and a build made against the wrong origin is rebuilt, not reconfigured.
No `task` target builds, signs or installs one; the steps below call `flutter` and `xcrun` directly,
which the repository's rule allows (`task` triggers native tools, it never replaces them) but means
there is nothing to keep the steps honest. They are written down here for that reason.

The sign-in mail's link returns to the installed app through `prudent://auth-callback`. That scheme is
declared in `client/ios/Runner/Info.plist` (`CFBundleURLTypes`) and read by `app_links`; Supabase must
list it among its Redirect URLs (`docs/persistent-environment.md`, section 3), or the link opens the
wrong page and nothing says so.

## Before the first build

- **Xcode, with the Apple ID signed in** (Xcode → Settings → Accounts) and the team set on the Runner
  target (`DEVELOPMENT_TEAM` is already in `client/ios/Runner.xcodeproj`, with automatic signing and the
  bundle id `com.jlogicsoftware.prudent`). An Apple Development certificate must be in the login
  keychain: `security find-identity -v -p codesigning`.
- **The phone** is paired with the Mac and visible to `flutter devices` (a wireless pairing was enough),
  and **Developer Mode** is on (Settings → Privacy & Security; it restarts the phone).
- **The service answers.** `gcloud run services describe SERVICE_NAME --project=GCP_PROJECT
  --region=GCP_REGION --format='value(status.url)'` gives `SERVICE_URL`; `curl "$SERVICE_URL/api/v1/health"`
  should answer 200. Take the origin from there, not from this repository.

## Build, install, launch

```sh
SERVICE_URL=$(gcloud run services describe SERVICE_NAME --project=GCP_PROJECT \
  --region=GCP_REGION --format='value(status.url)')

cd client
flutter build ios --release \
  --dart-define=ZEN_ENV=prd --dart-define=ZEN_PLATFORM=ios \
  --dart-define=ZEN_API_URL="$SERVICE_URL" \
  --dart-define=ZEN_AUTH_REDIRECT_URI=prudent://auth-callback

flutter install -d DEVICE_ID --release
xcrun devicectl device process launch --device DEVICE_ID com.jlogicsoftware.prudent
```

`flutter devices` lists `DEVICE_ID`. The Xcode build took about 45 seconds on the run that worked.

- **`--release`, not debug.** A debug build of a Flutter app cannot be started from the home screen on a
  recent iOS; release (or profile) can. This is Flutter's documented behaviour, and it is why the steps
  never use `flutter run` without it.
- **The origin is in the build.** `task build:web` searches the web bundle for the host and fails if it is
  missing; nothing does that for the iOS build, so the only evidence is that the app reached the server. If sign-in fails
  with a network error, rebuild before suspecting the server.
- **The first launch is refused** with "invalid code signature, inadequate entitlements or its profile
  has not been explicitly trusted" until the developer profile is trusted on the phone: Settings →
  General → VPN & Device Management → the Apple Development entry → Trust. That is the expected first-run
  step for a build signed with your own certificate, not a defect.

## What went wrong on the way, and what it meant

| What was seen | Cause | Fix |
|---|---|---|
| `Error: could not code sign the application` with `Unable to log in with account … The login details … were rejected` and `No profiles for 'com.jlogicsoftware.prudent' were found` | Xcode's Apple ID session had expired; with it gone, automatic signing cannot create the provisioning profile, although the certificate is still in the keychain | Sign in again in Xcode → Settings → Accounts. It is interactive and cannot be scripted or retried |
| `Flutter` writes `client/ios/Podfile` (or `client/macos/Podfile`) back, or `task verify:swiftpm` fails | A plugin that was added or updated has no Swift package, so Flutter fell back to CocoaPods for it. The runners carry no CocoaPods integration (ADR-083), so that is a second build description arriving unannounced | Find the plugin (`flutter build ios` names it) and use a version or an alternative that ships a Swift package; do not commit the Podfile. `pod install` is never part of building Prudent |
| `git status` shows `client/ios/Runner.xcodeproj/project.pbxproj` and `Runner.xcscheme` modified after the build | The toolchain (Xcode 27.1) rewrote the project file: `objectVersion` 54 to 60 and a reordered package reference | **Not part of this work, and not committed.** Decide on it separately; `git checkout -- client/ios` discards it |

## What this showed (2026-10-27, one iPhone, iOS 26.6)

Observed by the owner on the installed build, against the persistent environment:

- **Registration and the mail return.** A new user registered; the confirmation mail arrived; the link
  first opened in the browser, which offered to open Prudent, and the app opened normally and **signed the
  user in immediately**. `prudent://auth-callback` therefore works end to end on a device, which was the
  open question in `docs/persistent-environment.md`.
- **Signing in with an existing user** worked, before that.
- **The signed-in screens load.** The overview showed a balance; Settings opened; the language was
  changed, with all three offered (`en`, `uk`, `pl`); a new account was created and one expense recorded
  on it, and it appeared in the balance. That is an authenticated read and write of Prudent messages on a
  native binary against the deployed service, once, by hand.

## What it did not show

- **The mail was not good, and that is not fixed.** The confirmation mail was almost empty and its
  address looked like phishing (the owner's description; the message itself was not inspected for this
  record). It is Supabase's built-in sender and default template, and the link names the Supabase
  project's host, so the link opens the browser on that host first. Tracked as #186 (sender and
  relay), #187 (Prudent's own template in `en`, `uk`, `pl`) and jZenDev/jZen#154 with #188 (the link);
  ADR-079. Do not give this build to anyone but the owner until they land.
- **No notification has been seen to fire**, and none can be: a plan's reminder cannot be switched on in
  the UI yet (CLAUDE.md, M5).
- **Both transports, as an automated check, are still unproven** (#159). The above was a person using the
  app; it is not `verify:deploy` reading a Prudent message as a signed-in user.
- **The deployed service is older than `main`.** It predates the privacy export and erasure, the
  readiness probe and the dormancy mail. Settings → "Privacy and data" was not tried and is expected to
  fail against it until a redeploy, which needs the mail relay and `SUPABASE_SECRET_KEY`
  (`docs/persistent-environment.md`, section 3).
- **Re-signing was not observed.** What kind of Apple Developer account the team is was not recorded here.
  Apple's documented limits are that a build signed through a free Apple ID stops launching after 7 days
  and must be installed again with the steps above, while a paid account's development profile lasts
  longer. Which applies, and when this build stops launching, is unknown until it happens.
- **One device, one iOS version, one Mac.** Nothing was run on an iPad, on a second iPhone, or on a
  Mac other than the owner's.
- **No distribution.** This is a development install on a registered device. TestFlight and the App Store
  are not set up, and not part of #155.

## After the user is deleted from Supabase

Deleting a user in the Supabase dashboard (Authentication → Users) does **not** delete Prudent's rows
for them; the signed-in erasure routes do (ADR-075), and so does the operator route (ADR-074), but the
deployed service does not have them yet. Until a redeploy the rows are removed by hand, in one
transaction, in the order `PrudentDataEraser` uses. That was done once on 2026-10-27 for a throwaway
test user with a SQL script, which is deliberately **not** kept here: the order is the eraser's, a table
added later would be missing from a copy, and `PrivacyCoverageTest` is what notices that. After a
redeploy, use `POST /api/v1/admin/privacy/users/{userId}/erase` instead.
