import type { CapacitorConfig } from '@capacitor/cli';

const serverUrl = process.env.SPOTLIGHT_SERVER_URL || 'http://20.196.25.174:3000';

const config: CapacitorConfig = {
  appId: 'ae.trustsky.spotlight',
  appName: 'TrustSky Spotlight',
  webDir: 'www',
  server: {
    url: serverUrl,
    cleartext: true, // Remove when HTTPS is ready
    allowNavigation: ['20.196.25.174', 'spotlight.trustsky.tii.ae', '*.mapbox.com'],
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
