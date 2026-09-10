# PushNotification

Swift package providing the Strivacity push notification SDK for iOS.

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

That image ships **SwiftFormat 0.63.0** preinstalled and the workflow uses it as-is, so install
the same version locally to avoid formatting disagreements between your machine and CI:

```bash
brew install swiftformat   # currently 0.63.0, matching the runner
swiftformat --version      # expect 0.63.0
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

Run the Swift package tests from this directory with:

```bash
swift test
```

This builds and runs all tests in the `PushNotificationTests` target.
