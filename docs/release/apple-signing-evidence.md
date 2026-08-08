# Kalories Apple Signing Evidence

Captured at `2026-08-08 18:01:35 JST (+0900)` for Apple Team
`YMUG864233` and bundle ID `com.ryuaistudio.kalories`.

## Current result

Status: `BLOCKED_BY_APPLE_LOGIN`.

The Apple signing branch is isolated at `codex/kalories-apple-signing`. No
Apple Developer capability, identifier, certificate, provisioning profile,
App Store Connect record, archive, upload, review, or TestFlight state was
changed in this attempt.

## Verified local evidence

- Xcode Release settings use Team `YMUG864233` and bundle ID
  `com.ryuaistudio.kalories`.
- One valid Apple Distribution identity matches Team `YMUG864233`.
- No matching Apple Development identity was found for that team.
- Two provisioning profiles are installed under Xcode's current profile
  directory, but zero match the exact team and bundle.
- Therefore zero valid App Store profiles currently prove production App
  Attest entitlement for this app.
- No `KALORIES_ASC_*`, `ASC_*`, `APP_STORE_*`, `APPLE_*`, or `FASTLANE_*`
  credential variables were available to the process.

## Authentication boundary

Both the in-app browser and the user's Chrome session redirected the exact
Apple Developer identifiers URL to Apple's sign-in page. Codex did not enter,
read, request, or store an Apple password, verification code, recovery detail,
cookie, or session token.

## Required continuation

The user must manually sign in to Apple Developer in the opened Chrome tab and
complete any Apple-controlled 2FA. After the user confirms that login is
complete, continue on this branch with these exact gates:

1. Verify the selected Apple team is `YMUG864233`.
2. Locate exactly one explicit identifier for
   `com.ryuaistudio.kalories`; do not create a duplicate.
3. Enable only the App Attest capability if it is absent, then read it back.
4. Create or refresh one App Store distribution profile for that identifier.
5. Download/install the profile and verify its team, bundle, expiry,
   distribution type, and production App Attest entitlement without recording
   its UUID or certificate contents.
6. Run local signing/profile gates and commit sanitized evidence only.

Archive, export, App Store Connect app creation, TestFlight upload, review, and
public release remain out of scope.
