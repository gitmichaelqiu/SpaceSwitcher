# Repository Guidelines

## Project Structure & Module Organization

SpaceSwitcher is a macOS Swift app built with Xcode. The `SpaceSwitcher/` directory contains the application target:

- `Models/` holds rule, dock, and shared settings data types.
- `Services/` contains integrations and state managers for Spaces, Dock, permissions, launch-at-login, status bar, and updates.
- `Views/` contains SwiftUI views and the settings view controller.
- `Resources/`, `Assets.xcassets/`, `Fonts/`, and `SpaceSwitcherIcon.icon/` contain localized strings, acknowledgements, screenshots, icons, and bundled fonts.
- `SpaceSwitcher.xcodeproj/` contains the Xcode project and shared `SpaceSwitcher` scheme.

Keep new feature logic in the appropriate service/model/view layer, and keep user-facing strings in `Resources/Localizable.xcstrings`.

## Build, Test, and Development Commands

Run commands from the repository root:

```bash
xcodebuild -project SpaceSwitcher.xcodeproj -scheme SpaceSwitcher -configuration Debug build
xcodebuild -project SpaceSwitcher.xcodeproj -scheme SpaceSwitcher -configuration Release build
```

The first command builds a local debug app; the second validates the release configuration. Open `SpaceSwitcher.xcodeproj` in Xcode to run the app and inspect settings UI. The project currently has no XCTest target, so no automated test command is configured; perform a manual smoke test after changes.

## Coding Style & Naming Conventions

Follow existing Swift style: four-space indentation, one type per logical file, `UpperCamelCase` for types, and `lowerCamelCase` for properties, methods, and local values. Prefer small, focused `ObservableObject`/SwiftUI components and keep side effects in services. Match existing Xcode formatting and avoid unrelated reformatting. No separate lint or formatter configuration is checked in.

## Testing Guidelines

For every change, build the target and manually verify launch, status-bar behavior, settings navigation, and any affected SpaceAPI, Dock, permission, or update flow. UI changes should be checked on the supported macOS version range and include updated screenshots when useful.

## Commit & Pull Request Guidelines

Use imperative, scoped Conventional Commit-style messages such as `fix(dock): verify tile metadata` or `feat(ui): add rule editor`. Keep commits focused. Pull requests should explain the behavior change, link an issue when applicable, describe manual verification, and include before/after screenshots for UI changes. Bug reports should include macOS and app versions plus reproduction steps.

## Configuration & Permissions

The app requires macOS 13.0 or later and relies on DesktopRenamer’s SpaceAPI for current-space information. Changes involving Dock control or accessibility/login permissions should document required user permissions and failure behavior.
