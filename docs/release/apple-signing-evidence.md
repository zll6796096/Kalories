# Kalories Apple Signing Evidence

Initial preflight captured at `2026-08-08 18:01:35 JST (+0900)` for Apple Team
`YMUG864233` and bundle ID `com.ryuaistudio.kalories`. Authorized continuation
completed at `2026-08-08 18:26:23 JST (+0900)`.

## Current result

Status: `PASS_APPLE_SIGNING_FOUNDATION`.

The Apple signing branch is isolated at `codex/kalories-apple-signing`. The
approved Apple Developer identifier, App Attest capability, and one App Store
profile were changed. No App Store Connect app record, archive, export, upload,
review, TestFlight processing, invitation, public release, or storefront state
was changed.

## Completed Apple Developer changes

- The selected team was read back as `YMUG864233`.
- No existing `com.ryuaistudio.kalories` identifier was present before the
  mutation, so one explicit App ID named `Kalories` was registered.
- App Attest was enabled during registration and read back as checked on the
  identifier detail page.
- No existing `Kalories App Store` profile was present before the mutation.
  One App Store Connect distribution profile with that exact name was generated
  for the exact identifier and the one valid local Distribution certificate.

## Verified local signing evidence

- Xcode Release settings use Team `YMUG864233` and bundle ID
  `com.ryuaistudio.kalories`.
- One valid Apple Distribution identity matches Team `YMUG864233`.
- No matching Apple Development identity was found for that team.
- Exactly one installed profile matches the team and bundle. Its name is
  `Kalories App Store`, it is unexpired, it is an App Store distribution
  profile, it contains production App Attest entitlement, and its embedded
  certificate matches the valid local Distribution identity.
- Release signing is scoped only to the Kalories app target. Swift Package
  dependency targets do not receive the provisioning profile setting.
- A generic-device Release build succeeded with Xcode-managed profile sync.
- The signed app passed the distribution release gate: bundle and Firebase app
  identity matched, the Firebase configuration was packaged exactly, the
  signature verified, and the signed App Attest entitlement was exactly
  `production`.
- No `KALORIES_ASC_*`, `ASC_*`, `APP_STORE_*`, `APPLE_*`, or `FASTLANE_*`
  credential variables were available to the process.

## Authentication boundary

The user completed Apple login and any Apple-controlled verification manually
in Chrome. Codex did not enter, read, request, or store an Apple password,
verification code, recovery detail, cookie, or session token. The portal
download endpoint was blocked by Chrome automation, so the generated profile
was synchronized through Xcode using the exact target-scoped Release signing
configuration.

## Resolved implementation issue

The first Xcode sync attempt supplied `PROVISIONING_PROFILE_SPECIFIER` as a
global command-line override. Xcode propagated it into Firebase and
GoogleUtilities package targets, which do not support provisioning profiles.
The fix moved the Release signing settings to the Kalories app target in the
XcodeGen specification and regenerated the project. A regression test proves
that the profile and Distribution identity occur exactly once in the generated
project.

No profile UUID, certificate fingerprint/content, Apple account identity, or
signed binary is stored in this repository.

## Remaining boundaries

Archive, export, App Store Connect app creation, TestFlight upload, review, and
public release remain out of scope. This signing PASS does not advance any of
those gates.
