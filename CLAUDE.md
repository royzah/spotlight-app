# TrustSky Spotlight — Mobile App (Capacitor)

## What This Is

Capacitor 8 native shell wrapping the TrustSky Spotlight web app (Next.js).
Loads from a remote server with native tile caching for offline map support.

## Quick Reference

- **App ID**: `ae.trustsky.spotlight`
- **Server**: `https://20.203.65.213` (will become `https://spotlight.trustsky.tii.ae`)
- **Web app repo**: `../trustsky-spotlight/` (runtime dependency only, no shared files)
- **Min Android**: SDK 29 (Android 10)
- **Min iOS**: 16.0

## Build Commands

```bash
# Docker (anyone can build — no local Android SDK needed)
docker compose run android-build        # → ./build-output/app-debug.apk
docker compose run android-release      # → ./build-output/app-release.aab

# Local (requires Android SDK / Xcode)
npx cap sync android && npx cap run android
npx cap sync ios && npx cap run ios

# Fastlane
fastlane android build_dev
fastlane ios build_dev
```

## Architecture

### Remote Server Mode

The app loads the web app from the remote server URL. `www/index.html` is an offline fallback shown when the server is unreachable.

### Offline Tile Caching

- **Android**: `shouldInterceptRequest()` on `BridgeWebViewClient` — intercepts HTTPS tile requests transparently
- **iOS**: `WKURLSchemeHandler` for `cachedtile://` scheme — web app rewrites tile URLs via `transformRequest` in `useMapbox.ts`
- **TypeScript plugin**: `src/plugins/OfflineTilesPlugin.ts` bridges to native code

### Web App Changes (in trustsky-spotlight repo)

- `src/hooks/useMapbox.ts`: `transformRequest` rewrites tile URLs to `cachedtile://` on iOS Capacitor
- `src/lib/auth.ts`: `sameSite` cookie configurable via `COOKIE_SAME_SITE` env var

## Key Files

- `capacitor.config.ts` — Capacitor configuration (server URL, plugins)
- `src/plugins/definitions.ts` — OfflineTilesPlugin TypeScript interface
- `android/app/src/main/java/ae/trustsky/spotlight/plugins/` — Android native plugin
- `ios/App/App/Plugins/OfflineTilesPlugin/` — iOS native plugin
- `Dockerfile` + `docker-compose.yml` — Containerized Android builds
- `fastlane/Fastfile` — Build + deploy lanes for both platforms

## Important Notes

- Server is HTTPS with a **self-signed cert**. Native trust is scoped to `20.203.65.213` only:
  - Android: `network_security_config.xml` trust-anchor → `res/raw/spotlight_server.pem` (gitignored — provision the `comms-utm-ca` cert before building)
  - iOS: `CustomViewController.swift` server-trust handler accepts the cert for that host
  - The cert must carry `IP Address:20.203.65.213` in its SAN, or hostname verification fails
  - Remove both once a publicly trusted cert (e.g. `spotlight.trustsky.tii.ae`) is in place
- `npx cap sync` must be run after any config changes before building
- Plugin registration in `MainActivity.java` must be BEFORE `super.onCreate()`
