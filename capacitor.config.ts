import type { CapacitorConfig } from '@capacitor/cli';

const serverUrl = process.env.SPOTLIGHT_SERVER_URL || 'https://20.203.65.213';

const config: CapacitorConfig = {
  appId: 'ae.trustsky.spotlight',
  appName: 'TrustSky Spotlight',
  webDir: 'www',
  server: {
    url: serverUrl,
    cleartext: false, // Server is HTTPS. Private-CA cert trust is handled natively
    // (Android: network_security_config trust-anchor; iOS: CustomViewController).
    allowNavigation: ['20.203.65.213', '*.mapbox.com'],
  },
  // SplashScreen and StatusBar are handled natively (not via plugins)
  // due to Capacitor 8.0.x Swift PM incompatibilities.
  //   Splash: Android styles.xml Theme.SplashScreen, iOS LaunchScreen.storyboard
  //   StatusBar: Android styles.xml, iOS Info.plist + CustomViewController
  android: {
    allowMixedContent: true,
  },
  ios: {
    contentInset: 'automatic',
    scheme: 'TrustSky Spotlight',
  },
};

export default config;
