# Roadmap

Focus Island’s local, offline timer remains the supported core experience throughout this roadmap. The [roadmap tracking issue](https://github.com/zeapsu/FocusIsland/issues/7) links the work below. Items in the Future proposals milestone are not product commitments.

## Published issues

| Area | Issue | Milestone |
| --- | --- | --- |
| Multi-display behavior and accessibility | [#1](https://github.com/zeapsu/FocusIsland/issues/1) | v1 stabilization |
| Developer ID signing and notarization | [#2](https://github.com/zeapsu/FocusIsland/issues/2) | v1 stabilization |
| HealthKit companion feasibility | [#3](https://github.com/zeapsu/FocusIsland/issues/3) | Future proposals |
| Private local personal statistics | [#4](https://github.com/zeapsu/FocusIsland/issues/4) | Future proposals |
| Optional product telemetry | [#5](https://github.com/zeapsu/FocusIsland/issues/5) | Future proposals |
| Optional Apple and Google sign-in | [#6](https://github.com/zeapsu/FocusIsland/issues/6) | Future proposals |

## Proposal details

### [Stabilization and accessibility](https://github.com/zeapsu/FocusIsland/issues/1)

**Problem.** The single-island display rule needs broader testing across physical displays, Spaces, notch geometries, and accessibility configurations.

**Scope.** Test and improve predictable display selection, native full-screen availability, keyboard access, VoiceOver labels, contrast, and Reduce Motion behavior.

**Acceptance criteria.** Documented behavior passes on supported macOS versions and on both notched and rectangular displays; controls have meaningful accessibility labels; visual animation respects Reduce Motion.

**Non-goals.** Multiple simultaneous islands, a general window manager, or a dashboard.

**Dependencies.** Hardware and macOS-version test coverage.

**Status.** Proposed.

### [Developer ID signing and notarization](https://github.com/zeapsu/FocusIsland/issues/2)

**Problem.** Ad-hoc signed builds require a first-launch approval and are unsuitable for broad distribution.

**Scope.** Add a reproducible Developer ID signing and notarization release process, then document the verified install path.

**Acceptance criteria.** A fresh download verifies with Gatekeeper on a clean supported Mac; the release process does not expose signing credentials; update archives verify correctly.

**Non-goals.** Requiring an account for Focus Island or weakening macOS security settings.

**Dependencies.** Apple Developer Program credentials, protected CI secrets, and release validation hardware.

**Status.** Proposed.

---

### [Assess a HealthKit companion integration](https://github.com/zeapsu/FocusIsland/issues/3)

**Problem.** Some people may want a focus/break routine to appear alongside their activity habits, but the current macOS app does not use HealthKit.

**Scope.** Evaluate a privacy-preserving iPhone or Apple Watch companion concept before any implementation. Define exactly which data types, if any, would be useful; confirm platform support and entitlement requirements; prototype permission copy and deletion behavior.

**Acceptance criteria.** A written feasibility decision names the supported platforms, proposed data types, user benefit, permission prompts, storage boundaries, deletion flow, and reasons to decline the feature if it cannot be justified. The design follows Apple’s fine-grained authorization model and treats missing or limited data as ambiguous.

**Non-goals.** Reading or writing health data in the current macOS utility, inferring medical conclusions, passive background collection, or making HealthKit a requirement for the timer.

**Dependencies.** Apple HealthKit capability and entitlements, companion-app product decision, privacy review, and real-device validation. Apple documents HealthKit as a permissioned repository for iPhone and Apple Watch health and fitness data; macOS availability alone does not establish a useful desktop product integration. See [HealthKit](https://developer.apple.com/documentation/healthkit) and [authorizing access](https://developer.apple.com/documentation/healthkit/authorizing-access-to-health-data).

**Status.** Proposal; no HealthKit code or entitlement is present.

### [Add private local personal statistics](https://github.com/zeapsu/FocusIsland/issues/4)

**Problem.** People may want a lightweight history of their own completed focus and break blocks without turning the app into a productivity dashboard.

**Scope.** Design an optional local-only history with a clear retention limit, export/delete controls, and a small summary that remains secondary to the timer.

**Acceptance criteria.** Statistics remain on-device by default, can be fully deleted from Settings, exclude free-text content and health data, and do not change timer behavior. The UI states its retention rule and does not create a streak, score, leaderboard, or gamified loop.

**Non-goals.** Accounts, cloud sync, social comparison, automatic behavioral profiling, or medical/wellness claims.

**Dependencies.** Data-model design, migration plan, privacy review, and user research on whether the feature stays appropriately small.

**Status.** Proposal; Focus Island currently has no session history.

### [Consider optional product telemetry](https://github.com/zeapsu/FocusIsland/issues/5)

**Problem.** Maintainers may need aggregate reliability signals to improve releases, while users should not have to trade privacy for a timer.

**Scope.** Propose an explicit opt-in telemetry design limited to operational events such as update-check outcomes and crash/reliability signals. Document every event, retention period, processor, and deletion path before collecting anything.

**Acceptance criteria.** Telemetry is off by default; the app works identically when it remains off; consent can be withdrawn; no timer contents, session history, identifiers for advertising, or HealthKit data are sent; the documented schema is testable against the implementation.

**Non-goals.** Analytics by default, sale or sharing of data, targeted advertising, cross-app tracking, or hidden diagnostics.

**Dependencies.** Privacy policy, legal review, backend design, data-processing agreement where relevant, and a clear incident/deletion process.

**Status.** Proposal; Focus Island currently sends no product analytics. Sparkle update checking is documented separately and has system-profile reporting disabled.

### [Evaluate optional Apple and Google sign-in](https://github.com/zeapsu/FocusIsland/issues/6)

**Problem.** An account may eventually support a user-requested cross-device feature, but it would add security, privacy, and operational responsibilities absent from the local app.

**Scope.** First define a concrete account-backed feature and a backend threat model. If justified, design optional Sign in with Apple and Google OAuth using native authorization, PKCE, Keychain token storage, short-lived sessions, account deletion, and recovery/support flows.

**Acceptance criteria.** The product benefit is documented before authentication is built; anonymous offline use remains complete; the backend verifies tokens and does not trust a client-supplied identity; PKCE and Keychain are used on supported clients; users can delete their account and associated server data; Apple and Google flows receive security review.

**Non-goals.** Requiring login to time focus blocks, passwords managed by Focus Island, social profiles, or sync without a defined deletion and conflict-resolution model.

**Dependencies.** Accepted cloud-sync/account product decision, backend and privacy policy, OAuth client registration, secure token verification, account-deletion service, and security review.

**Status.** Proposal; Focus Island currently has no accounts, cloud sync, Apple sign-in, or Google sign-in.
