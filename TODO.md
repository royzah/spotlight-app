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

- [ ] Generate Android release keystore (`keytool -genkey -v -keystore trustsky-spotlight.keystore ...`)
- [ ] Base64-encode keystore and add as GitHub secret `ANDROID_KEYSTORE_BASE64`
- [ ] Create Apple Developer App ID for `ae.trustsky.spotlight`
- [ ] Set up Fastlane Match git repo for iOS certificates
- [ ] Configure App Store Connect API key
- [ ] Add all required GitHub secrets (see README)
- [ ] Test full CI/CD pipeline: push a `v1.0.0` tag, verify artifacts

## App Store Readiness

- [ ] Design proper splash screen assets (currently using dark background only)
- [ ] Add adaptive icon foreground/background for Android (currently using raster icon)
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

## Performance

- [ ] Measure cold start time on both platforms
- [ ] Profile tile cache read/write performance with large cache (10K+ tiles)
- [ ] Consider SQLite for cache metadata instead of file-per-tile approach
