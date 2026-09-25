# PushNotification

A push-based multi-factor authentication SDK for iOS. This SDK enables secure authentication flows by allowing enrolled devices to receive and respond to push-based challenges.

## What This SDK Does

The SDK handles two core flows:

- **Enrollment**: Register a device with a backend issuer using a one-time enrollment grant (delivered via QR code or deep link).
- **Challenge Resolution**: Receive push notifications containing authentication challenges and resolve them

The SDK does **not**:
- Scan QR codes or manage deep links — your app owns the camera and URL handling
- Register for push tokens, or detect when one rotates — your app owns APNs registration and token management, and calls `updateDeviceToken` to report a new one (see [Handling Enrollments](#handling-enrollments))
- Display notifications — your app decides what appears on screen
- Manage challenge UI — your app renders the challenge and collects the user's decision

## Integration Guide

These examples assume a SwiftUI app. Remote-notification handling itself is a `UIApplicationDelegate`/`UNUserNotificationCenterDelegate` concern regardless of UI framework — a SwiftUI app wires one in with `@UIApplicationDelegateAdaptor`:

```swift
@main
struct MyApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
```

The examples below assume `AppDelegate` owns the SDK instance and conforms to both delegate protocols.

### 1. Add the SDK to Your Project

Add the package in Xcode via **File → Add Package Dependencies…** with the repository URL, or add it directly to `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/strivacity/push-notification-sdk-ios", from: "<version>")
]
```

```swift
.target(
    name: "MyApp",
    dependencies: [
        .product(name: "PushNotification", package: "push-notification-sdk-ios")
    ]
)
```

> **Note:** Replace `<version>` with the latest release version. The URL above is a placeholder pending actual publication details.

### 2. Instantiate the SDK

Create a single SDK instance at app startup, typically owned by your `AppDelegate` or a dependency-injected singleton:

```swift
import PushNotification

let sdk = PushNotification(storage: DefaultPushNotificationStorage())
```

The SDK instance is app-scoped. One instance serves all issuers your device is enrolled against. You do not need to close it — it lives for the process lifetime.

#### Configuration

**`storage`** — A `PushNotificationStorage`, which stores each enrollment's keypair together with the record of the enrollment itself, and signs with the keypair. The SDK ships `DefaultPushNotificationStorage`, which uses NIST P-256 keys backed by the Secure Enclave where available and keeps each enrollment, key and details together, in a single Keychain item. It needs no entitlement or setup.

`PushNotificationStorage` is a plain protocol — a custom implementation can store keys and enrollments however it likes. See [Storage Extension Point](#storage-extension-point).

**Hardware-backed keys are required by default.** The Simulator has no Secure Enclave at all and will fail enrollment with `PushNotificationError.softwareBackedKey`. For development on the Simulator, opt into software keys explicitly:

```swift
let storage = DefaultPushNotificationStorage(allowSoftwareBackedKeys: true)
```

Keep `allowSoftwareBackedKeys: true` only in debug builds or CI, never in production-facing builds. A build that never explicitly allows this cannot silently end up signing with a software key.

### 3. Handle Enrollment

Enrollment requires:
1. An enrollment grant (parsed from a scanned QR code or deep link)
2. The current push token (to which the SDK refers to as "Device Token"), and which kind of token it is (`DeviceTokenType.apns` for a native APNs token — the SDK doesn't infer this, since more than one is valid on iOS; e.g. FCM is also usable via `.fcmToken`/`.fcmFid`)
3. A user-friendly device name (required). It must be 1-64 characters (after trimming), or `enrollDevice` throws `PushNotificationError.invalidDeviceName`.

**💡 Tip:** A good default for the device name is `UIDevice.current.name`.

**⚠️ APNs tokens arrive as `Data`, not a string.** Convert it before passing it to the SDK:

```swift
let deviceToken = rawDeviceToken.map { String(format: "%02x", $0) }.joined()
```

#### Parse the enrollment grant

Your app handles QR scanning and deep linking. Once you have the scanned string or deep-link URL, parse it into an enrollment grant:

```swift
import PushNotification

do {
    let grant = try EnrollmentGrant.parse(scannedURL)
} catch PushNotificationError.invalidGrant {
    // Malformed grant — show an error to the user
} catch PushNotificationError.invalidIssuer {
    // The issuer parameter isn't an absolute https URL
}
```

#### Call enrollDevice

```swift
Task {
    do {
        let enrollment = try await sdk.enrollDevice(
            grant: grant,
            deviceToken: apnsTokenString, // converted from the raw Data token above
            deviceTokenType: .apns,
            deviceName: userChosenName    // Must be 1-64 characters (after trimming), or throws .invalidDeviceName
        )
        // Success — the device is now enrolled
    } catch PushNotificationError.alreadyEnrolled {
        // This issuer + account is already enrolled on this device
        // Un-enroll first if you want to replace it
    } catch PushNotificationError.enrollmentRejected {
        // Backend refused the enrollment — not retryable
        // The user needs a fresh enrollment grant
    } catch PushNotificationError.softwareBackedKey {
        // Running on the Simulator without allowSoftwareBackedKeys = true
    }
}
```

### 4. Handle Incoming Challenge Pushes

A challenge push commonly arrives as a silent/background notification, handled in your `AppDelegate`:

```swift
import PushNotification
import UIKit

final class AppDelegate: NSObject, UIApplicationDelegate {
    let sdk: PushNotification = // ... get your SDK instance ...

    func application(
        _ application: UIApplication,
        didReceiveRemoteNotification userInfo: [AnyHashable: Any],
        fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void
    ) {
        guard let messageData = MessageData.from(userInfo: userInfo) else {
            completionHandler(.noData)
            return
        }

        Task {
            do {
                guard try await sdk.canHandleMessage(messageData) else {
                    completionHandler(.noData)
                    return
                }
                // Fetch the full challenge detail
                let challenge = try await sdk.handleMessage(messageData)
                // Show your challenge UI — see the Challenge section below
                showChallengeUI(challenge)
                completionHandler(.newData)
            } catch {
                // Something went wrong fetching the challenge detail
                completionHandler(.failed)
            }
        }
    }
}
```

#### Handling a Tapped Notification

If the push also carries a visible alert (not silent), the user may tap it instead of the app already being open. Unlike the split Android needs between `onCreate`/`onNewIntent` depending on launch mode, iOS routes every tap through one delegate callback regardless of whether the tap launched the app fresh or resumed it from the background:

```swift
import PushNotification
import UserNotifications

final class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    let sdk: PushNotification = // ... get your SDK instance ...

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        defer { completionHandler() }

        guard let messageData = MessageData.from(userInfo: response.notification.request.content.userInfo) else {
            return
        }

        Task {
            guard (try? await sdk.canHandleMessage(messageData)) == true else { return }
            do {
                let challenge = try await sdk.handleMessage(messageData)
                showChallengeUI(challenge)
            } catch {
                // Something went wrong fetching the challenge detail
            }
        }
    }
}
```

Register this delegate (e.g. `UNUserNotificationCenter.current().delegate = self`) during app launch, typically alongside where you request notification authorization.

`MessageData.from(userInfo:)` returns `nil` if the payload carries nothing for the SDK — safe to call unconditionally on any notification payload.

### 5. Render the Challenge and Collect a Response

The SDK returns a `Challenge` enum with two cases. Your app renders appropriate UI based on the case:

```swift
switch challenge {
case let .simple(simple):
    // Show a simple approve/deny screen
    showApproveDenyUI(challenge) { userApproved in
        let resolution = userApproved ? simple.approve() : challenge.deny()
        submitResolution(resolution)
    }
case let .contextMatching(contextMatching):
    // Show the context-matching screen with the offered options
    showContextMatchingUI(contextMatching.options) { selectedOption in
        do {
            let resolution = try contextMatching.select(selectedOption)
            submitResolution(resolution)
        } catch {
            // selectedOption wasn't one of contextMatching.options — an integration error if it
            // reaches here, since the UI should only ever offer options from that list.
        }
    }
}
```

### 6. Submit the Resolution

Once the user has made a decision, sign and submit it:

```swift
func submitResolution(_ resolution: ChallengeResolution) async {
    do {
        let result = try await sdk.resolveChallenge(resolution)
        switch result {
        case .ok:
            // Resolution accepted by the backend
            showSuccess()
        case .notOk:
            // Resolution rejected by the backend (including explicit denials)
            showFailure()
        }
    } catch {
        // Network error, signing error, etc.
        showError(error)
    }
}
```

## Concepts and Flows

### Enrollment Flow

**Enrollment** establishes a trusted relationship between a device, a user account, and a backend issuer.

1. **Parse the grant** — Your app scans a QR code or handles a deep link, extracting:
   - The issuer URL (which backend cluster this enrollment targets)
   - An account ID (the user's account at that issuer)
   - The device name (how the user will recognize this device in their enrollment list)

2. **Generate and register** — Call `enrollDevice` with the grant, the device's push token, and the device name. The SDK:
   - Generates a keypair for this (issuer, account) pair and stores it locally, together with the enrollment's details, for future lookups and token updates (the private key never leaves the device)
   - Sends the public key to the backend along with the one-time token from the grant
   - Removes the keypair and the enrollment again if the backend refuses or can't be reached

3. **Constraints:**
   - One device can hold at most one enrollment per (issuer, account) pair. Attempting a second enrollment for the same pair fails with `PushNotificationError.alreadyEnrolled` — un-enroll first to replace it.
   - Enrollments survive deleting and reinstalling the app. The shipped storage keeps each key and its enrollment record together in the Keychain, which iOS does not clear when an app is deleted. After a reinstall, `listEnrollments` still returns the earlier enrollments, and enrolling the same (issuer, account) pair again fails with `PushNotificationError.alreadyEnrolled`. Your app's push token typically changes on reinstall, so report the new one with `updateDeviceToken` for each listed enrollment.
   - Keychain items are not restored to a different device, so neither keys nor enrollment records carry over to a new device restored from a backup.
   - If your app is terminated while `enrollDevice` is waiting for the backend, the enrollment stays recorded on the device even though the backend may never have accepted it. It then appears in `listEnrollments`, and `updateDeviceToken` for it is refused by the backend. Call `unenrollDevice` to remove it — the local removal completes even though the backend call fails.
   - The one-time token in the grant is single-use. A failed enrollment cannot be retried with the same token; a fresh grant is required.

### Challenge Flow

**Challenges** are MFA requests pushed to an enrolled device. The user reviews the request and makes a decision.

1. **Push notification arrives** — A push reaches the enrolled device's push token. Your app receives it (see [Handle Incoming Challenge Pushes](#4-handle-incoming-challenge-pushes)) and calls `canHandleMessage` to check if this is an enrollment the SDK can handle.

2. **Fetch challenge details** — Call `handleMessage` to retrieve the full challenge from the backend. The SDK returns a challenge object containing:
   - The challenge type: **Simple** (approve/deny) or **ContextMatching** (pick from options)
   - For simple: nothing more
   - For context matching: a list of options the user will see
   - Metadata (device, location, time — context for the user's decision)
   - Expiration time (an ISO 8601 / RFC 3339 instant string, e.g. `2026-10-01T14:30:00Z`)

3. **Render UI and collect decision** — Your app renders a screen appropriate to the challenge type and captures the user's choice:
   - **Simple**: Approve or Deny buttons
   - **ContextMatching**: Select one of the offered options (or deny)

4. **Submit the resolution** — Call `resolveChallenge` with the user's decision. The SDK signs the response with the enrolled keypair and sends it to the backend.

5. **Get the result** — The backend returns `ResolutionResult.ok` or `ResolutionResult.notOk`.

**User denial is not an error.** An explicit refusal from the user returns `ResolutionResult.notOk` normally — it's a legitimate outcome. The SDK reserves errors for actual failures (network errors, missing key, etc.).

**Expiry and timestamps.** The SDK provides the challenge's expiration time (`challenge.expiresAt`, an ISO 8601 / RFC 3339 instant string, e.g. `2026-10-01T14:30:00Z`) for your app to display or warn about, but does not enforce it — the backend is the authority.

## Storage Extension Point

`PushNotificationStorage` stores each enrollment's keypair together with the record of the enrollment itself, and signs with the keypair. The SDK ships `DefaultPushNotificationStorage`; you may replace it to:

- Integrate with an existing key management system
- Use a different secure storage backend

```swift
public protocol PushNotificationStorage: Sendable {
    /// The public key currently in use for this issuer and account, or `nil` if none is stored.
    /// Only a single key exists for an issuer and account combination.
    func getPublicKey(issuer: String, accountId: String) async throws -> Jwk?

    /// Signs `data` with the key of this id, returning the signature as a base64url string. The
    /// data is a raw string; the implementation is responsible only for signing, not for JWT
    /// structure.
    ///
    /// - Throws: `PushNotificationError.notEnrolled` if no enrollment is recorded for this issuer
    ///   and account — checked first. `PushNotificationError.storageFailure` if an enrollment is
    ///   recorded but no key of that id is stored.
    func createSignature(issuer: String, accountId: String, keyId: String, data: String) async throws -> String

    /// Generates a new keypair for this issuer and account, records the enrollment it belongs to
    /// (its `keyId` is the returned key's `kid`), and returns the key's public half.
    ///
    /// - Throws: `PushNotificationError.alreadyEnrolled` if a key for this issuer and account
    ///   already exists.
    func createEnrollment(issuer: String, accountId: String, userName: String?, deviceName: String?) async throws -> Jwk

    /// Every enrollment currently recorded. A read failure degrades to an empty list.
    func listEnrollments() async -> [Enrollment]

    /// Removes every key and enrollment record held for this issuer and account. Silently does
    /// nothing if none is stored.
    func removeEnrollment(issuer: String, accountId: String) async throws
}
```

How the SDK uses an implementation:

- `enrollDevice` and `hasEnrollment` decide whether an enrollment exists from `listEnrollments`, not from the presence of a key. The other methods look the key up with `getPublicKey`, and `createSignature` rejects a key that has no enrollment record with `notEnrolled`.
- Before creating an enrollment, the SDK calls `removeEnrollment` for that issuer and account, so `createEnrollment` only has to handle the case where nothing is stored. If the backend then refuses the enrollment, the SDK calls `removeEnrollment` again.
- If `removeEnrollment` throws during `unenrollDevice`, the SDK rethrows your error unchanged, in preference to any backend failure from the same call. Throw a `PushNotificationError.storageFailure` so callers can handle it like the SDK's other storage errors.

Store each enrollment's key and record together, so that one is never left without the other.

### JWK Format

Public keys are returned as `Jwk` values containing:
- `kid` — A unique identifier for the key (client-generated; the SDK uses it to retrieve the key for signing)
- `alg` — The signing algorithm used (e.g. `ES256` for NIST P-256)
- `members` — A dictionary of JWK fields (e.g. `x`, `y`, `crv` for elliptic curve keys)

The JWK must contain only the public half. The SDK validates that the private-key member `d` is not present; if it is, enrollment fails.

### Supported Algorithms

The SDK enforces a closed allowlist of signing algorithms. Currently, only ES256 (NIST P-256) is accepted. A `PushNotificationStorage` implementation that returns a key with an unsupported algorithm will fail at enrollment with `PushNotificationError.unsupportedAlgorithm`.

## Handling Enrollments

### Check Whether You're Enrolled

Before calling `enrollDevice`, check if an enrollment already exists. This answers from the enrollments recorded in storage — the same check `enrollDevice` makes:

```swift
let isEnrolled = try await sdk.hasEnrollment(issuer: issuer, accountId: accountId)
if isEnrolled {
    // Enrollment exists; un-enroll first if you want to replace it
}
```

### Un-Enroll a Device

```swift
Task {
    do {
        try await sdk.unenrollDevice(issuer: issuer, accountId: accountId)
        // Device is un-enrolled
    } catch PushNotificationError.notEnrolled {
        // Nothing to un-enroll
    } catch PushNotificationError.unenrollmentRejected, PushNotificationError.networkFailure {
        // The backend call failed, but the local enrollment was removed anyway.
        // The backend may still believe the device is enrolled.
    } catch {
        // Looking up the key, or removing the enrollment locally, failed
    }
}
```

**Important:** The local keypair and enrollment record are always deleted, even if the backend call fails. This prevents a device from becoming stuck with an un-recoverable enrollment if the backend is temporarily unreachable. The trade-off is that the backend may retain a stale enrollment record. If the local removal itself fails, `unenrollDevice` throws the storage's error (`PushNotificationError.storageFailure` with the shipped storage), even when the backend call failed too, and the backend's failure is lost. With the shipped storage the key and record are one Keychain item, so nothing was removed and calling `unenrollDevice` again repeats the whole operation.

### List Enrollments

Every enrollment this device holds — across every issuer and account, including ones your app never itself initiated (e.g. restored from a backup):

```swift
let enrollments = await sdk.listEnrollments()
// Enrollment(issuer, accountId, keyId, userName, deviceName)
```

This is what makes reporting a refreshed push token possible without your app keeping its own record of enrollments.

### Report a Refreshed Push Token

Your app owns APNs registration, including detecting when the token rotates. iOS calls `application(_:didRegisterForRemoteNotificationsWithDeviceToken:)` whenever registration succeeds — including the very first time and on any subsequent refresh. When that happens, list what's enrolled and decide for yourself what to do with each — update all of them silently, warn the user first, or skip ones you don't recognise:

```swift
extension AppDelegate {
    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        let tokenString = deviceToken.map { String(format: "%02x", $0) }.joined()

        Task {
            for enrollment in await sdk.listEnrollments() {
                do {
                    try await sdk.updateDeviceToken(
                        issuer: enrollment.issuer,
                        accountId: enrollment.accountId,
                        deviceToken: tokenString,
                        deviceTokenType: .apns
                    )
                } catch PushNotificationError.tokenUpdateRejected {
                    // Backend refused the update for this one enrollment
                } catch {
                    // Anything else, e.g. `networkFailure` — retry later, or skip
                }
            }
        }
    }
}
```

## Error Handling

The SDK reports failures as a single `PushNotificationError` enum, not a hierarchy of exception types. Catch a specific case directly (`catch PushNotificationError.someCase`), or inspect `.code` (a stable, greppable string such as `"already_enrolled"`), `.message`, `.status` (the backend's HTTP status, where applicable), and `.cause` (the underlying error, where one exists) for logging and error reporting:

- **`.alreadyEnrolled(issuer:accountId:)`** — An enrollment already exists for this issuer + account. Un-enroll first.
- **`.enrollmentRejected`** — The backend refused enrollment (e.g. invalid one-time token). Not retryable.
- **`.unenrollmentRejected`** — The backend refused un-enrollment. The local enrollment is removed regardless.
- **`.invalidGrant`** — The enrollment grant URL is malformed or missing required parameters.
- **`.invalidDeviceName`** — The device name (after trimming) isn't 1-64 characters.
- **`.notEnrolled`** — No enrollment exists for this issuer + account.
- **`.tokenUpdateRejected`** — The backend refused a device token update.
- **`.softwareBackedKey`** — The device could only produce a software-backed key, but you did not opt into allowing them.
- **`.challengeUnavailable`** — The push payload is not a challenge this SDK can handle, or the backend refused it or returned one this SDK can't read, or failed its resolution.
- **`.unsupportedChallengeType(challengeType:)`** — The backend sent a challenge type not supported by this SDK version.
- **`.storageFailure`** — The `PushNotificationStorage` implementation returned invalid data, or key generation/signing failed, or the local key and enrollment record could not be read or removed.
- **`.networkFailure`** — The backend could not be reached, or the response was unreadable.
- **`.unsupportedAlgorithm(algorithm:accepted:)`** — The key algorithm is not in the allowlist.
- **`.invalidIssuer(issuer:)`** — The issuer URL is malformed.
- **`.invalidChallengeOption(challengeId:)`** — `Challenge.ContextMatching.select(_:)` was called with an option not among those the challenge offered.

Errors thrown by a custom `PushNotificationStorage` are rethrown unchanged. So are errors the shipped storage doesn't wrap, such as a CryptoKit error from the Secure Enclave, so a `catch` for these cases isn't exhaustive.

Error messages never contain sensitive material (tokens, keys, JWTs).

## Running on the Simulator

The Simulator has no Secure Enclave at all. The SDK requires hardware-backed keys by default, so enrollment will fail with `PushNotificationError.softwareBackedKey`.

To develop on the Simulator, explicitly opt into software keys:

```swift
let storage = DefaultPushNotificationStorage(allowSoftwareBackedKeys: true)
```

**Keep this flag enabled only in debug builds.** A production build should never allow software-backed keys.

## Development

### Prerequisites

Install the toolchain with [Homebrew](https://brew.sh):

```bash
brew install lefthook swiftformat swiftlint
```

#### Matching the CI tool versions

The [Code Quality](.github/workflows/code-quality.yml) workflow runs on `macos-latest`, which
currently resolves to the **macOS 26 Arm64** image. Its full list of preinstalled packages —
including the Xcode and Swift tool versions — is published here:

- [macOS 26 Arm64 installed packages](https://github.com/actions/runner-images/blob/main/images/macos/macos-26-arm64-Readme.md)
- [Available runner images](https://github.com/actions/runner-images#available-images) — check
  which image `macos-latest` points to, since it moves with each new macOS release

That image ships **SwiftFormat 0.64.2** preinstalled and the workflow uses it as-is, so install
the same version locally to avoid formatting disagreements between your machine and CI:

```bash
brew install swiftformat   # currently 0.64.2, matching the runner
swiftformat --version      # expect 0.64.2
```

If yours is older, upgrade it:

```bash
brew upgrade swiftformat
```

Homebrew's current `swiftformat` stable happens to equal the runner's version. If they ever
diverge — a new runner image, or a Homebrew bump ahead of it — the runner image list above is the
source of truth, and an exact version can be pinned with
[Mint](https://github.com/yonaskolb/Mint) (`mint install nicklockwood/SwiftFormat@<version>`).

SwiftLint is **not** preinstalled on the runner; the workflow installs it with
`brew install swiftlint` at run time, so your Homebrew version matches as long as both are current.

### Activate the git hooks

Hooks are declared in [.lefthook.yml](.lefthook.yml) but are **not** active until installed
into your local clone. Run this once after cloning:

```bash
lefthook install
```

That installs a `pre-commit` hook which runs `swiftformat --lint .` and `swiftlint .`, blocking
the commit if either fails — the same two checks the Code Quality workflow runs on pull requests.
Verify it is wired up with:

```bash
lefthook run pre-commit
```

To remove the hooks again, run `lefthook uninstall`.

### Linting

Rules live in [.swiftformat](.swiftformat) and [.swiftlint.yml](.swiftlint.yml). Run the same
checks the hook and CI run:

```bash
swiftformat --lint .
swiftlint .
```

To apply formatting fixes rather than just reporting them:

```bash
swiftformat .
```

Note that lefthook lints the **staged** content, not your working tree — it stashes unstaged
changes first. After fixing a violation, `git add` the file before retrying the commit, or the
hook will keep reporting the old version.

### Testing

Run the test suite from this directory with:

```bash
xcodebuild test -scheme PushNotification -destination 'platform=iOS Simulator,name=iPhone 17'
```

Swap `iPhone 17` for any simulator you have installed (`xcrun simctl list devices` lists them).

This builds and runs every test in the `PushNotificationTests` target. Plain `swift test` does
**not** work for this package: `Package.swift` declares only `.iOS(.v15)` as a supported platform,
so with no macOS platform declared, SwiftPM falls back to an old default macOS deployment target
where `URLSession.data(for:)` (used by `PushNotificationClient`) isn't available, and the build
fails. `xcodebuild` builds against the declared iOS minimum and runs the tests in the simulator
instead.

To run a single suite or test during development, add `-only-testing:`, e.g.
`-only-testing:PushNotificationTests/PushNotificationEnrollDeviceTests`.

## Security Considerations

- **Keys are hardware-backed by default.** The shipped `DefaultPushNotificationStorage` uses the Secure Enclave where available.
- **Enrollment details are protected by the Keychain.** The shipped `DefaultPushNotificationStorage` stores each enrollment's details (issuer, account id, user name, device name) in the same Keychain item as its key, readable after the device's first unlock and never migrated to another device. A custom `PushNotificationStorage` implementation may use a different storage mechanism with its own protection model.
- **The one-time token is single-use.** A failed enrollment cannot be retried with the same token.
- **The challenge value prevents replay.** It is a single-use value the backend invalidates on first use, and it is bound into the resolution JWT.
- **Private keys never leave the device.** Signing happens in the Secure Enclave; only signatures cross the network.
- **The default is the secure option.** Software-backed keys must be opted into explicitly.
