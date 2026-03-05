# TODO

## High Priority

- [ ] Test on Android emulator -- verify login, map rendering, tile caching
- [ ] Test on iOS simulator -- verify login, map rendering, `cachedtile://` scheme
- [ ] Offline test -- browse map area, enable airplane mode, confirm cached tiles render
- [ ] Trigger UAE region download via plugin, verify progress events and cache stats
- [ ] Set `COOKIE_SAME_SITE=lax` on server, verify auth works in Capacitor WebView

## HTTPS Migration

- [ ] Obtain `https://spotlight.trustsky.tii.ae` TLS certificate
- [ ] Update `capacitor.config.ts` server URL and set `cleartext: false`
- [ ] Remove cleartext ATS exception from `Info.plist`
- [ ] Remove cleartext domain from `network_security_config.xml`

## Signing and Distribution

### Android (done)

- [x] Generate Android release keystore
- [x] Base64-encode keystore and add GitHub secrets
      (`ANDROID_KEYSTORE_BASE64`, `ANDROID_KEYSTORE_PASSWORD`,
      `ANDROID_KEY_ALIAS`, `ANDROID_KEY_PASSWORD`)

### iOS (requires Apple Developer Program membership)

Certificates and provisioning via Fastlane Match:

1. Create a **private** GitHub repo (e.g., `trustsky-certificates`).
2. Run Match setup on a Mac with Xcode:

   ```bash
   fastlane match init        # choose "git", paste the repo URL
   fastlane match development # generates dev cert + profile
   fastlane match appstore    # generates distribution cert + profile
   ```

   Match will ask for an encryption password -- save it.

3. Add these GitHub secrets:

   | Secret           | Where to get it                                |
   | ---------------- | ---------------------------------------------- |
   | `MATCH_GIT_URL`  | The private cert repo URL                      |
   | `MATCH_PASSWORD` | Encryption password from `fastlane match init` |
   | `APPLE_TEAM_ID`  | Apple Developer portal > Membership > Team ID  |

App Store Connect API key (for TestFlight upload):

1. Go to App Store Connect > Users and Access > Integrations > API Keys.
2. Click "Generate API Key", give it "App Manager" role.
3. Download the `.p8` file (can only download once).
4. Base64-encode it: `base64 -w 0 AuthKey_XXXXXXXXXX.p8`
5. Add these GitHub secrets:

   | Secret                             | Where to get it                       |
   | ---------------------------------- | ------------------------------------- |
   | `APP_STORE_CONNECT_API_KEY_ID`     | Shown on the API keys page            |
   | `APP_STORE_CONNECT_ISSUER_ID`      | Shown at the top of the API keys page |
   | `APP_STORE_CONNECT_API_KEY_BASE64` | Base64 of the `.p8` file              |

### Remaining

- [ ] Create Apple Developer App ID for `ae.trustsky.spotlight`
- [ ] Test full CI/CD pipeline: push a `v1.0.0` tag, verify artifacts

## App Store Readiness

- [x] Design proper splash screen assets (TrustSky logo on dark background)
- [x] Add adaptive icon foreground/background for Android
- [ ] Write App Store / Play Store listing copy
- [ ] Prepare screenshots for both stores
- [ ] Privacy policy URL (required by both stores)
- [ ] Set up Firebase Crashlytics or equivalent crash reporting

## Tile Caching Improvements

- [ ] Add UI in web app for triggering offline region downloads
- [ ] Show download progress indicator
- [ ] Add cache size display and clear button in settings
- [ ] Implement cache eviction policy (LRU or TTL-based)
- [ ] Test with large regions -- monitor memory usage during bulk downloads
- [ ] Cache Mapbox style JSON, glyphs, and sprites (currently tiles only in bulk download)

## Push Notifications

- [ ] Add `@capacitor/push-notifications` plugin
- [ ] Integrate with server-side notification system for drone alerts
- [ ] Configure Firebase Cloud Messaging (Android) and APNs (iOS)

## Deep Linking

- [ ] Configure Universal Links (iOS) and App Links (Android)
- [ ] Handle `trustsky.tii.ae/drone/:id` deep links to open specific drone view

## Mobile-Specific Features

The mobile app can offer features not possible in the browser. Detection
is straightforward -- the web app checks `Capacitor.isNativePlatform()`
and `Capacitor.getPlatform()` at runtime to conditionally enable
mobile-only UI and behavior. Native code lives in this repo
(`spotlight-app`), UI and logic in the web app (`trustsky-spotlight`).

### Field Operator Features

- [ ] **Operator location on map** -- show the operator's live GPS
      position on the drone map using `@capacitor/geolocation` with
      background mode. Useful for field teams coordinating near
      active flights.
- [ ] **Biometric login** -- fingerprint or face unlock to skip
      password entry on trusted devices. Use `capacitor-native-biometric`
      plugin. Stores session token in secure enclave.
- [x] **Keep screen awake** -- prevent screen timeout during active
      drone monitoring sessions. Plugin installed, hook at
      `trustsky-spotlight/src/hooks/useKeepAwake.ts`.
- [ ] **Haptic alerts** -- vibration feedback for critical events
      (geofence breach, loss of telemetry, low battery warning).
      Use `@capacitor/haptics`.

### Communication and Sharing

- [x] **Share drone report** -- native share sheet to send a drone
      status snapshot via WhatsApp, email, or other apps. Plugin
      installed, helper at `trustsky-spotlight/src/lib/share.ts`.
- [ ] **QR code scanner** -- scan a drone's QR code to instantly
      pull up its profile and telemetry. Use `@capacitor-community/barcode-scanner`.

### Offline and Connectivity

- [ ] **Offline telemetry queue** -- when connectivity drops, queue
      telemetry submissions locally and sync when back online.
      Use `@capacitor/network` to detect status changes.
- [x] **Auto-download tiles on Wi-Fi** -- detect Wi-Fi and
      automatically pre-cache UAE tiles. Plugin installed, hook
      at `trustsky-spotlight/src/hooks/useAutoTileDownload.ts`.

### Notifications

- [ ] **Geofence proximity alerts** -- notify when the operator
      physically enters or exits a restricted flight zone, using
      device GPS and the zone boundaries already defined in the
      web app.
- [ ] **Background drone alerts** -- push notifications when a
      monitored drone triggers an alert (battery critical,
      signal lost, geofence breach) even when the app is
      backgrounded.

### Device Integration

- [ ] **Camera capture for incident reports** -- attach photos
      taken on-site to drone incident reports. Use
      `@capacitor/camera`.
- [ ] **Voice-to-text notes** -- hands-free note-taking during
      field operations using `@capacitor-community/speech-recognition`.
- [x] **Compass heading overlay** -- device compass bearing for
      orienting toward drones. Plugin installed, hook at
      `trustsky-spotlight/src/hooks/useCompassHeading.ts`.

## Performance

- [ ] Measure cold start time on both platforms
- [ ] Profile tile cache read/write performance with large cache (10K+ tiles)
- [ ] Consider SQLite for cache metadata instead of file-per-tile approach
