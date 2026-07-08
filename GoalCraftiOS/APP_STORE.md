# Screen Test — App Store Submission Pack

Everything on our side for an App Store submission. The remaining blockers (Apple
Developer account, signing, review) are Apple's process, not code.

## App identity
- **Name:** Screen Test
- **Subtitle (≤30):** Your portrait, in progress
- **Bundle ID:** `com.btyt.screentest` (matches the App Store Connect record; internal, not user-visible)
- **Version / Build:** 1.0 (1)
- **Primary category:** Productivity  ·  **Secondary:** Lifestyle
- **Age rating:** 4+

## URLs (static pages in `frontend/web/`, deploy via GitHub Pages workflow)
Live host is GitHub Pages at the `/goalcraft/` base path (NOT Cloudflare — README is stale).
These 404 until the next frontend deploy publishes the new pages.
- **Privacy Policy:** https://harrolee.github.io/goalcraft/privacy/
- **Support:** https://harrolee.github.io/goalcraft/support/
- **Marketing / About:** https://harrolee.github.io/goalcraft/about/
- **Terms (EULA):** https://harrolee.github.io/goalcraft/terms/

## Promotional text
Name who you're becoming — then count the proof, one small mark at a time.

## Description
Screen Test is a goal tracker with a point of view: you don't repeat affirmations,
you accumulate evidence. Declare the identity you're growing into, define the
handful of metrics that actually make it real, and log your progress as you go.

The name says it: a screen test is a rehearsal for the role you're about to play.
This is where you keep the tally of becoming that person.

• Identity-first goals — start with who you're becoming, not a generic checklist
• Custom metrics — track anything: songs released, sessions attended, deals closed
• Targets & trends — set a number to chase and watch your cumulative progress
• A ledger you'll want to open — elegant, focused, quietly theatrical
• Gentle reminders — optional evening nudges to keep you honest
• Private by design — your data is yours; delete everything anytime

## Keywords
goal,goals,habit,tracker,metrics,identity,progress,discipline,motivation,productivity,screen test

## App Privacy (nutrition label)
- **Data used to track you:** None.
- **Data linked to you:** Contact Info → Email Address (account sign-in);
  User Content → your goals, metrics, and logged entries.
- **Data not collected:** Location, contacts, browsing history, advertising data,
  health data, usage/analytics SDKs.
- **Account deletion:** In-app (⋯ → Settings → Delete Account) and via support email.
  Deletes the user row and cascades all goals/metrics/entries.
- **Sign in with Apple:** Supported (required because a third-party login/Auth0 is offered).

## Screenshots to capture (6.9" + 6.5")
1. Login ("Manifest the life by its numbers")
2. Dashboard hero + featured metric (Songs Released)
3. The Ledger (multiple metrics)
4. Metric detail with the trend chart
5. New Goal ("Who are you becoming?")

## Review notes (paste into App Store Connect)
- Sign in with Apple is on the login screen. No demo account needed; the app also
  offers a first-run flow. If a reviewer account is required, provide one from Auth0.
- Backend is a private FastAPI service; the app is a client to it.

## OPEN ITEMS (need the human / Apple account)
1. **Apple Developer Program** enrollment ($99/yr) — enrollment can take 24–48h.
2. **Signing:** set `DEVELOPMENT_TEAM` in `project.yml`, add the **Sign in with Apple**
   capability + entitlement (needs the paid team), then archive & upload.
3. **Confirm the Pages domain** — `goalcraft.pages.dev` is assumed; update
   `AppLinks.base` (SettingsView.swift) and this doc if different.
4. **Support email** — currently `halzinnia@gmail.com`; swap for a branded, monitored
   inbox if desired (privacy/terms/support pages + `AppLinks.support`).
5. **Backend production URL + real Auth0** — point `GOALCRAFT_API` at the deployed
   backend and turn OFF `DEV_AUTH_BYPASS`.
6. **Deploy `frontend/web/{privacy,terms,about,support}`** so the URLs resolve.

## Build (once signing is set up)
```bash
cd GoalCraftiOS
xcodegen generate
xcodebuild -project GoalCraftiOS.xcodeproj -scheme GoalCraftiOS \
  -configuration Release -sdk iphoneos -archivePath build/GoalCraft.xcarchive archive
# then Organizer → Distribute App → App Store Connect
```
