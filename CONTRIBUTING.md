# Contributing to Capd

Thanks for helping improve Capd. Bug fixes, product improvements, tests, and
documentation updates are welcome.

## Requirements

- macOS 26 or later
- Xcode 26.3
- Node.js 24 when working on the documentation site

## Set up the project

```sh
git clone https://github.com/jamiedavenport/capd.git
cd capd
./Scripts/bootstrap.sh
swift build
swift test --parallel
```

`bootstrap.sh` resolves Swift dependencies and configures the repository's Git
hooks. The pre-commit hook formats staged Swift files; CI also runs strict
formatting checks.

## Project layout

- `CapdKit` contains the data model, store, capture pipeline, and search.
- `CapdCLI` builds the `capd` command-line tool.
- `CapdAgent` builds the background enrichment worker.
- `CapdApp` builds the menu-bar app.
- `CapdAppUI` contains shared app views and presentation models.
- `CapdShareExtension` builds the macOS share-sheet extension.
- `CapdHandoff` handles messages between the extension and app.

## Before opening a pull request

Format and test the project:

```sh
swift format --in-place --recursive Sources Tests Package.swift
swift format lint --strict --recursive --parallel Sources Tests Package.swift
swift test --parallel
```

Use a [Conventional Commit](https://www.conventionalcommits.org/) message for
each commit. Keep changes focused and include tests for behavior changes.

The CLI's JSON fields and exit-code behavior are stable interfaces. Update the
golden tests in `Tests/CapdCLITests` whenever an intentional CLI contract change
is required.

## Documentation

Customer documentation lives in `docs/content` and is built with Blume.

```sh
cd docs
npm ci
npm run doctor
npm run build -- --strict
```

Write about behavior that exists today. Keep customer-facing explanations in
plain language, and preserve the current technical names used by commands,
paths, bundles, and background services.

## Build the app locally

`Scripts/package-app.sh` produces a complete `capd.app` and `.dmg` with an ad-hoc
signature:

```sh
Scripts/package-app.sh
```

Set `CODESIGN_IDENTITY` when a real signing identity is required.

## Release process

Pushing a `v*` tag matching `CapdKit.version` starts the release workflow. It:

1. Builds a universal `arm64` and `x86_64` app.
2. Bundles the app, CLI, agent, and share extension.
3. Signs, notarizes, and staples the release.
4. Publishes the `.dmg` to GitHub Releases.
5. Updates the Homebrew cask in `jamiedavenport/homebrew-tap`.

Signing secrets are available only to the tag-triggered release workflow. The
regular CI workflow builds and tests without them.
