# README
## Overview
This is a pretty basic Swift/SwiftUI grocery and meal planning app. I built it because I live with my girlfriend now, and can no longer keep all my grocery lists, cooking plans, and monthly spending totals in my head only. This is just a way to easily distribute that knowledge, while avoiding using a Shared Note, which kinda sucked to use.
## Features
- Shared grocery and shopping list with real-time updates
- Meal calendar for the following and previous week.
- Monthly grocery receipt tracker, with aggregated monthly spending totals split by person.
- Data sharing by group/household, and no limit on groups per user.
## Notes
Because I am poor, the backend is hosted on a GCP e2-micro instance that should be free to run as long as I stay below certain usage limits. Ideally I won't see more than 10ish active users in the most extreme case, so this should be fine. It uses a web socket to keep both our apps updated as we each make changes to the shopping list or meal calendar, so the iOS app requires Starscream. The backend uses gin and gorilla/websocket for the web server and web socket implementation, respectively, as well as pgx for interfacing with a simple PostgreSQL db. Auth is handled using simple JWTs with a 30-day refresh token.
