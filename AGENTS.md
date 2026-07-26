# Repository Guidelines

## Project Structure & Module Organization

AudioSwitch is a native macOS 13+ menu-bar application written in Swift 6 and built with Swift Package Manager. Keep Core Audio logic in `Sources/AudioSwitchCore/`: hardware access, device descriptors, switching coordination, and service state belong there. Keep SwiftUI/AppKit presentation and login-item behavior in `Sources/AudioSwitch/`. The executable self-check suite is `Checks/AudioSwitchCoreChecks/main.swift`; it supplies mocks alongside integration checks. Packaging metadata and generated icon inputs live in `Support/`; distribution and verification scripts are in `tools/`. Documentation images belong under `assets/`.

## Build, Test, and Development Commands

- `swift build` builds all SwiftPM products for development.
- `swift run AudioSwitch` launches the menu-bar app from source.
- `swift run AudioSwitchCoreChecks` runs the executable checks. It enumerates local Core Audio devices and rewrites the current default device values, so run it only on a machine with a working audio setup.
- `./tools/package_local_dmg.sh` builds a Universal 2, ad-hoc-signed local DMG; `./tools/verify_local_package.sh` validates the resulting bundle.
- `DEVELOPER_ID_APPLICATION="Developer ID Application: Name (TEAMID)" ./tools/release_notarized_dmg.sh` creates a signed, notarized public release. Do not commit `dist/`, `release/`, `.build/`, or generated icon files.

## Coding Style & Naming Conventions

Follow existing Swift style: four-space indentation, one import per line, braces on the declaration line, and trailing commas in multiline argument lists. Use `UpperCamelCase` for types, `lowerCamelCase` for members, and descriptive protocol names such as `AudioHardwareAccess`. Keep Core Audio calls behind the hardware-access abstraction so service logic remains mockable. Preserve Swift 6 concurrency annotations (`@MainActor`) when editing UI-observable state.

## Testing Guidelines

Add deterministic coverage to `AudioSwitchCoreChecks` for each behavior change. Name checks as short user-visible scenarios (existing checks use Chinese labels) and use `MockAudioHardware` for success, failure, and rollback paths. Run `swift build` and the check executable before opening a pull request; manually verify device switching and menu refresh when touching UI or listeners.

## Commit & Pull Request Guidelines

Recent history uses concise imperative subjects (for example, `Add illustrated feature overview to README`), without conventional-commit prefixes. Keep commits focused. Pull requests should explain the user-visible effect, list commands run, link the related issue when present, and include a screenshot or short recording for menu/UI changes. Call out any changes to signing, bundle identifiers, version numbers, or notarization requirements.
