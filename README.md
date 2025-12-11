# README
## Overview
This is a pretty basic Swift/SwiftUI grocery and meal planning app. I built it because I live with my girlfriend now, and can no longer keep all my grocery lists, cooking plans, and monthly spending totals in my head only. This is just a way to easily distribute that knowledge, while avoiding using a Shared Note, which kinda sucked to use.
## Notes
I don't have Apple Developer Program money, so to this is distributed via AltStore, via my source: jai-sinha.github.io/lebensmittel/source.json. I didn't really build this with anyone else in mind, though, so it's pretty personalized; the AltStore is just so we can download it on our phones and receive updates easily without having to deal with weekly Xcode signing.

Also because I don't have Apple Developer Program money, the backend is hosted on a GCP e2-micro instance that should be free to run as long as I stay below certain usage limits. Another reason why I don't really have anyone else in mind with this project; I don't really want to have to scale this up or out.

The backend uses a web socket to keep both our apps updated as we each make changes to the shopping list or meal calendar, so the iOS app requires Starscream; this should be the only frontend deps. The backend uses gin and gorilla/websocket for the web server and web socket implementation, respectively, as well as pgx for interfacing with the PostgreSQL db.
