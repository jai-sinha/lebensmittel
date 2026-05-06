# Changelog

All notable changes to this project will be documented in this file, to the best of my ability, and officially starting with 2.1.1

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

A/F/C/R

---

## [2.3.0] - 2026-05-05

### Added
- Offline mode! The app now works offline, with any changes made syncing to the server when you're back online
- Debug scheme + Config files for easier end to end testing

### Fixed
- Support page linking (got too markdown brained and forgot I was writing markup)
- Zero dollar/Itemless checkout bug

### Changed
- GuestHomeView wording and coloring
- Backend now can accept items list on receipt create, but old way of deriving item list is still retained as backup

## [2.2.2] - 2026-04-14

### Added
- Services and ServiceProtocols for proper iOS MVVM arch w/dependency injection

### Fixed
- Receipt creation bug
- Auth recursion bug

### Changed
- Made TextFields in Grocery and Meal Views dismissable
- Split auth, session, and group management into three distinct pieces

## [2.2.1] - 2026-04-09

### Changed
- Reorganized iOS networking and auth code
- Grocery item deletion to long press from swipe

## [2.2.0] - 2026-04-06

### Fixed
- WebSocket connection delegate clearing
- Meal plan date formatting

### Changed
- GroceriesView UI entirely, to look way better

---

## [2.1.1] - 2026-04-03

### Added
- Changelog filled in retroactively(!!)
- Pull-to-refresh on error states
- WebSocket connection check on app foreground
- WebSocket broadcast channel buffer, write mutex

### Fixed
- Remove vestigial optimistic updates
- MealsModel POST not going through WebSocket
- Login not using refresh token
- Gin release mode bug

### Removed
- `/routes` endpoint
- Unnecessary comments in main.go

---

## [2.1.0] - 2026-03-07

### Added
- Continue as guest functionality (no account required)
- Meal object auto-save on text field unfocus

### Changed
- Replace PUT endpoints with PATCH for partial object updates
- Update login gate with privacy clarification copy

---

## [2.0.0] - 2026-02-06

This release introduces user accounts, multi-user groups, and invite-based group sharing. The app now requires authentication in order to join a group, and group membership to do anything; it is no longer limited to personal use by my roommate and I.

### Added
- Users and groups tables with full CRUD and JWT auth
- Access/refresh token pair for longer-lived sessions
- Group-scoped WebSocket connections
- Group invite codes with expiry
- Group routes: get user groups, get active group, remove user from group
- Cascade group deletion across related tables, automatic cleanup of data from orphaned groups
- Auth wired into all existing API calls
- Group management with concurrency-safe AuthManager (nonisolated methods/types)
- Group creation and invite code UI in auth menu
- Prompt new users to create or join a group on first launch
- Delete user account
- Auth/account menu available across all views
- Privacy policy on GitHub Pages

### Fixed
- Clean up empty item edge cases in views

### Changed
- Reorg backend workspace with top-level folders and go modules

---

## [1.3.0] - 2025-12-11

This release rewrites the backend in Go with PostgreSQL, replaces Socket.IO with native WebSockets, and modernizes the iOS codebase to avoid bad patterns in AI code. This is meant to be step 1 towards more users, which requires a more performant backend given my machine constraints. I picked Go because it's fun :)

### Added
- Full backend rewrite in Go + PostgreSQL, preserving all prior Python/SQLite functionality
- Deploy Go backend to VM

### Fixed
- Itemless receipts backend bug

### Changed
- Switch from Socket.IO to native WebSockets
- Move API info endpoint from `/` to `/routes`
- Replace `ObservableObject` with `@Observable` macro
- Update colors, corner radii, and tab styling
- Remove `DispatchQueue` usage; clean up string formatting and font calls; fix button accessibility
- Update API base URL to new domain
- Cleaned meal plan update call

### Removed
- Legacy Python backend code
- Socket.IO package from iOS project

---

## [1.2.2] - 2025-11-24

### Fixed
- ShoppingModel inheritance bugs causing stale state

---

## [1.2.1] - 2025-11-19

### Changed
- Reduce data fetches to once on startup
- Reorganize and tweak receipts view layout

---

## [1.2.0] - 2025-11-03

### Added
- Collapsible grocery categories
- Swipe-to-delete for grocery items

### Changed
- Updated grocery UI to be more space-efficient
- Updated meals UI coloring
- Renamed and reorganize category names
- Grocery item coloring and dark mode support

---

## [1.0.0] - 2025-11-01

Initial public release. Covers all development from October 15 through November 1, 2025.

### Added
- Basic SwiftUI interface with Groceries, Meals, Shopping, and Receipts tabs
- Groceries CRUD with categories and search
- Meals view with calorie tracking
- Shopping list sorted by category
- Checkout flow with receipt generation
- Receipts view with monthly running totals; edit/delete receipt support
- WebSocket-based real-time updates for Groceries, Meals, Shopping, and Receipts
- Simple Flask/SQLite backend with full CRUD for groceries, meals, shopping, and receipts
- AltStore source JSON
- GitHub Actions workflow to publish AltStore source via GitHub Pages
- App icon and display name
- README
