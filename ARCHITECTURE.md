# Lebensmittel — Architecture Overview

## Summary
- **What it is:** A Swift/SwiftUI grocery and meal-planning app with shared lists, weekly meals, and monthly receipt tracking. Multi-group/household support with real-time sync.
- **Stacks:**  
  - **Backend:** Go 1.22+, Gin, PostgreSQL (pgx), Gorilla/WebSocket, JWT auth, CORS open, hosted on a small GCP e2-micro.  
  - **iOS:** SwiftUI + Observable macro, URLSession-based networking with token injection, Starscream WebSockets for live updates.
- **Realtime:** WebSocket channel per user with group-scoped broadcasts for grocery, meal, and receipt events.

## High-level Architecture
- **API layer:** Gin routes under `/api/*` for CRUD on groceries, meals, receipts, users, groups, invites, auth.
- **Auth:** JWT access (15m) + refresh (30d). Passwords hashed with bcrypt. Middleware enforces Bearer tokens and access-token type.
- **Data layer:** PostgreSQL via `pgxpool`. Database package encapsulates CRUD and transactional flows (e.g., receipt creation updates grocery items).
- **Realtime layer:** Gorilla/WebSocket manager with group subscription and server-side broadcasts when data changes.
- **Client:** SwiftUI app consuming REST and listening on WebSocket. Models handle optimistic-ish flows; WebSocket events drive live UI updates.

## Backend Details (Go)
- **Entry point:** `main.go`
  - Initializes DB, starts hourly cleanup of expired invite codes.
  - Sets up Gin in release mode, permissive CORS, and HTTP server (default port 8000).
  - Routes: `/health`, `/routes` (self-doc), `/ws` (WebSocket), `/api/*`.
- **Packages**
  - `auth`: JWT creation/validation, bcrypt hashing.
  - `middleware`: Auth middleware (Bearer, access-token type check, userID in context).
  - `database`: CRUD for grocery_items, meal_plans, receipts, users, groups, user_groups, join_codes; group deletion cascades related data; join code expiry cleanup; example data seeding helper used on group creation.
  - `handlers`:
    - Auth: register/login/refresh returns token pairs.
    - Grocery/Meal/Receipt: CRUD + WebSocket emits.
    - Group/User: CRUD, membership, active-group resolution (`X-Group-ID` header or first group), invite code generation/join.
    - Utils: active group resolution, example data generation on new group.
  - `websocket`:
    - Manages client registry and group subscriptions.
    - Broadcast channel supports optional group scoping to avoid cross-group leakage.
    - Events emitted on create/update/delete for groceries, meals, receipts; welcome message; echo; subscribe handling with membership validation.
- **Notable behaviors**
  - **Active group resolution:** If `X-Group-ID` provided, membership is verified; otherwise first user group is used.
  - **Receipts creation:** Pulls checked+needed grocery items into receipt, then resets their needed/checked flags in a transaction.
  - **Meal creation:** Replaces existing meal for a given date/group in a transaction.
  - **Group deletion:** Transactionally removes dependent rows across tables.
  - **Invite codes:** 6-char alphanum, 15m expiry, periodic cleanup.

## Data & API Model (conceptual)
- **User**: id, username (unique), email, password_hash, display_name.
- **Group**: id, name; membership via user_groups (many-to-many).
- **GroceryItem**: id, name, category, is_needed, is_shopping_checked, group_id, user_id.
- **MealPlan**: id, date, meal_description, group_id, user_id.
- **Receipt**: id, date, total_amount, purchased_by, items (JSON text), notes?, group_id, user_id.
- **JoinCode**: code, group_id, expires_at, created_by.
- **Key endpoints (protected unless noted)**:  
  - Auth: `POST /api/register`, `POST /api/login`, `POST /api/refresh` (public).  
  - Groceries: `GET/POST/PATCH/DELETE /api/grocery-items[/id]`.  
  - Meals: `GET/POST/PATCH/DELETE /api/meal-plans[/id]`.  
  - Receipts: `GET/POST/PATCH/DELETE /api/receipts[/id]`.  
  - Users: CRUD + `GET /api/users/me/groups`, `GET /api/users/me/active-group`.  
  - Groups: CRUD, membership add/remove, invite creation `POST /api/groups/:id/invite`, join via code `POST /api/groups/join`.  
  - WebSocket: `GET /ws?token=...&groups=gid1,gid2` (also supports Authorization header).

## WebSocket Events (server → client)
- `connected`
- Grocery: `grocery_item_created|updated|deleted`
- Meal: `meal_plan_created|updated|deleted`
- Receipt: `receipt_created|updated|deleted`
- Subscription request: client sends event `subscribe` with `groups: []`; server validates membership.

## iOS App Architecture (SwiftUI)
- **App root:** `lebensmittelApp` wires `AuthStateManager` and feature models; on auth success it starts `SocketService` and triggers initial fetch.
- **State & Models:**
  - `AuthStateManager`: checks auth, holds current user, groups, active group ID, group users; drives login state.
  - Feature models (`GroceriesModel`, `MealsModel`, `ReceiptsModel`, `ShoppingModel`): Observable, own local caches, perform REST via `NetworkClient`, and receive WebSocket-driven updates.
- **Networking:**
  - `AuthManager` (actor): handles register/login/refresh, token storage (Keychain), group ops, and user ops. Single-flight refresh and active-group fetch; injects `X-Group-ID` and `Authorization` headers via `NetworkClient`.
  - `NetworkClient`: wraps URLSession; retries once on 401 by refreshing token.
  - Base URL: `https://ls.jsinha.com/api`.
- **Persistence & Security:** Tokens, user, and activeGroupId stored in Keychain (`KeychainService`). JWT expiry parsing utility for proactive refresh.
- **Realtime:** `SocketService` (Starscream) connects to `wss://ls.jsinha.com/ws` with token and optional `groups` query; auto-reconnect with backoff; routes events to models.
- **Views:** SwiftUI screens for login, auth menu, groceries, shopping, meals, receipts, content shell.

## Domain Workflows
- **Join household:** User creates group → server seeds example data → invite code generated → another user joins via code → membership reflected; active group cached client-side.
- **Shopping flow:** User checks items in shopping mode → creates receipt → backend auto-consumes checked+needed items into receipt and resets flags → broadcast to group.
- **Meal planning:** One meal per date per group; creating a meal replaces existing date entry.
- **Realtime sync:** Any create/update/delete on groceries/meals/receipts triggers WebSocket broadcast scoped to group; clients update local state.

## Deployment & Ops
- **Runtime:** Go service on GCP e2-micro; default port 8000; env vars `PORT`, `DATABASE_URL`, `JWT_SECRET`, `SECRET_KEY`, `DEBUG`.
- **CORS:** Allow-all; methods GET/POST/PATCH/DELETE/OPTIONS; headers Origin, Content-Type, Accept, Authorization.
- **Health:** `/health` returns basic status.
- **Resilience:** Graceful shutdown on SIGINT/SIGTERM; WebSocket pings keep connections alive.

## Notable Implementation Choices
- **Group-aware WebSocket routing** avoids cross-tenant leaks.
- **Transactional mutations** for receipts and meals ensure data consistency.
- **Example data seeding** on group creation improves first-run UX.
- **Single-flight token refresh** reduces thundering herd on expiry.
- **Keychain-backed auth cache** with JWT expiry parsing for proactive refresh.

## Quick Start (conceptual)
1. Set `DATABASE_URL`, `JWT_SECRET`, `PORT` (optional).
2. Run backend: `go run main.go` (or build) in `backend/`.
3. iOS: configure scheme, ensure base URL `https://ls.jsinha.com` (baked in), run on device/simulator.
4. Create account → create group → invite/join → use groceries/meals/receipts; watch realtime sync.
