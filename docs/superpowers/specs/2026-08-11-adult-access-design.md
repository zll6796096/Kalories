# カロスキャン 18+ Access Design

Date: 2026-08-11

Status: Approved in conversation. This specification supersedes the general-
audience and calculated-age-only decisions in
`2026-08-10-japan-app-store-public-release-design.md`. It does not authorize a
change to LifeSnapAction or any other app.

## 1. Real Objective

Keep the public Japan release of カロスキャン compatible with the current
Gemini API Additional Terms while collecting the least possible age data.
Google's terms effective 2026-03-23 require API users to be at least 18 and
prohibit an API Client directed toward, or likely to be accessed by, people
under 18. カロスキャン uses Gemini `GenerateContent`, so the shipped app,
public disclosures, review instructions, and App Store age rating must express
one consistent 18+ boundary.

LifeSnapAction currently has no equivalent gate and is publicly rated 4+
despite using the same Gemini API family. Its existing App Store approval does
not waive Google's provider terms. That mismatch is recorded as a separate
follow-up risk; no LifeSnapAction file or App Store record is in this scope.

## 2. First-Principles Rule

Risk control comes before release speed. A visible App Store approval is not
evidence that a third-party provider contract is satisfied. The minimum useful
control is therefore an honest store rating plus an in-app boundary before any
photo selection, camera access, or analysis—not a legal paragraph that users
can bypass without seeing.

## 3. Approaches Considered

### 3.1 Selected: store-level 18+ plus one-time local confirmation

- Complete Apple's questionnaire truthfully, do not choose Kids, then use
  **Override to Higher Age Rating** so the Japan product page displays 18+.
- On first launch, show a localized age-access screen before the capture flow.
- Explain that the AI analysis service is available only to people aged 18 or
  older.
- Continue only after the user taps an explicit localized “I am 18 or older”
  action.
- Persist only a Boolean confirmation in `UserDefaults` on that device.
- Do not request or store birth date, legal name, identity document, account,
  or age-verification evidence.
- A user who has not confirmed cannot select a photo, open the camera, or call
  the analysis service.

This is the selected balance between the provider restriction and data
minimization. It is a self-attestation, not identity proof, so the App Store
rating and public 18+ wording remain required defense in depth.

### 3.2 Rejected: App Store 18+ rating only

The store rating improves discovery and parental-control behavior but does not
prove the installed app presented or enforced the boundary. A previously
installed, shared, or otherwise accessible copy could enter the analysis flow
without an explicit acknowledgement.

### 3.3 Rejected: birth date, ID, account, or third-party age verification

Stronger verification would add personal-data collection, retention, support,
security, and privacy obligations disproportionate to a free single-purpose
nutrition-estimation app. The provider terms do not justify collecting exact
birth dates or identity documents for this release.

## 4. Product Behavior

### 4.1 First launch

The root view resolves the saved app language and the local adult-access
Boolean before rendering the capture flow. With no confirmed Boolean, the app
renders only the age-access screen.

The screen contains:

- the product name;
- a clear “18 years and older only” heading;
- a short explanation that the app sends a meal photo to an AI analysis
  service only after the separate photo-transfer consent;
- a statement that people under 18 cannot use the app;
- an explicit “I am 18 or older” action;
- working privacy-policy and support links; and
- no camera, photo-picker, fixture, or analysis control.

The existing Japanese, Simplified Chinese, and English localization mechanism
provides the copy. Unsupported device languages continue to fall back to
Japanese.

### 4.2 Confirmation and persistence

Confirmation writes only `true` under the versioned key
`kalories.adult-access.confirmed.v1`. No `false` record is necessary. Once the
write succeeds in the process, the root replaces the gate with the normal
capture flow. Subsequent launches on the same installation read the Boolean
and do not ask again.

Uninstalling the app or clearing its local data may remove the confirmation,
in which case the next launch asks again. Confirmation is not synced, uploaded,
logged, attached to analysis requests, or treated as an account attribute.

### 4.3 Fail-closed boundary

The gate sits above every `AppScreen`, including DEBUG screenshot fixtures.
Unit and UI fixtures may inject an in-memory confirmed state for deterministic
tests, but Release code has no launch argument, environment variable, URL,
remote flag, or hidden control that bypasses the gate.

If local preference reading fails or yields an unexpected value, the app treats
the user as unconfirmed. If a future release changes the legal meaning of the
attestation, it must use a new versioned key and ask again.

## 5. Architecture and File Responsibilities

- `ios/Kalories/Features/AdultAccess/AdultAccessModel.swift` owns the versioned
  key, Boolean persistence adapter, observable confirmed state, and confirm
  action. It has no UI or network responsibility.
- `ios/Kalories/Features/AdultAccess/AdultAccessView.swift` owns the localized,
  accessible SwiftUI gate and legal/support links.
- `ios/Kalories/App/AppEnvironment.swift` constructs the live model from
  `UserDefaults.standard` and permits explicit test injection.
- `ios/Kalories/App/RootView.swift` renders `AdultAccessView` before switching
  over the existing analysis flow.
- `ios/Kalories/Resources/*/Localizable.strings` contains complete three-
  language age-access copy.
- focused unit and UI tests prove persistence, default-deny behavior, no
  pre-confirmation capture controls, confirmation transition, and subsequent-
  launch behavior.
- public privacy/support pages disclose the 18+ requirement and the exact
  local Boolean boundary.
- App Store metadata and review notes state 18+ and begin the reviewer steps
  with the confirmation action.

The existing second consent before sending a selected meal photo remains
unchanged. Age confirmation is eligibility acknowledgement; photo consent is
per-photo transfer authorization. One does not replace the other.

## 6. App Store and Public Disclosure

App Store Connect must:

1. answer the content questionnaire from shipped behavior;
2. keep Made for Kids off;
3. select **Override to Higher Age Rating** and choose 18+;
4. read back the Japan rating as 18+ before submission; and
5. retain the 18+ override consistently for this Gemini-backed release.

Apple documents that a developer may override a calculated rating upward and
must do so when an app's own minimum-age requirement exceeds the calculated
rating. The public privacy policy and support page must state that:

- the app is only for users aged 18 or older;
- the app asks once on-device for confirmation;
- only a Boolean is stored locally;
- no date of birth or identity document is collected; and
- the confirmation is not sent to Kalories, Google, Firebase, or Apple.

## 7. Scope Boundaries

### In scope

- native iPhone age-access model and view;
- three-language copy and accessibility identifiers;
- deterministic unit and UI tests;
- privacy/support page and metadata corrections;
- App Store 18+ override instructions and review notes;
- plan/evidence corrections that previously said general audience or 9+.

### Out of scope

- changing LifeSnapAction or another app;
- collecting birth date, legal identity, ID images, parental consent, or an
  account;
- remote age-verification vendors;
- analytics or telemetry for the confirmation;
- replacing Gemini;
- modifying the per-photo consent, nutrition contract, camera flow, backend,
  billing, territory, price, or monetization;
- claiming that a self-attestation proves the user's actual age.

## 8. Acceptance Criteria

- A fresh installation opens on the localized 18+ screen.
- Before confirmation, camera, library, fixture, and analyze controls do not
  exist in the accessibility tree and no provider request can be initiated.
- Tapping the explicit adult action reveals the existing capture flow.
- The exact versioned Boolean is the only new persisted value; no birth date or
  identity data is requested or stored.
- A subsequent launch on the same installation skips the gate.
- Japanese, Simplified Chinese, and English copy is complete and tested.
- Privacy and support pages state 18+, local-only Boolean persistence, no birth
  date/ID collection, and no transmission of the confirmation.
- Metadata and review notes match the shipped behavior.
- App Store Connect shows 18+ for Japan through the higher-rating override
  before submission.
- Existing native flow, public-page, web, backend, privacy-manifest, build, and
  release checks still pass.
- Git diff is reviewed and the worktree status is reported.

## 9. Verification

```bash
cd ios
xcodegen generate
xcodebuild test \
  -project Kalories.xcodeproj \
  -scheme Kalories \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro'
cd ..
.venv/bin/python -m unittest tests.test_public_pages -v
npm test
npm run lint
npm run build
git diff --check
git status --short --branch
```

The exact installed simulator may require selecting another available iPhone;
the implementation plan must resolve and record the real destination rather
than weakening the test scope.

## 10. Official References

- Gemini API Additional Terms, effective 2026-03-23:
  <https://ai.google.dev/gemini-api/terms>
- Apple age-rating setup and higher-rating override:
  <https://developer.apple.com/help/app-store-connect/manage-app-information/set-an-app-age-rating/>
