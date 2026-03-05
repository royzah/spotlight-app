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
  plugins: {
    SplashScreen: {
      backgroundColor: '#131318',
      launchAutoHide: true,
      autoHideDelay: 2000,
      showSpinner: false,
    },
    // StatusBar: removed @capacitor/status-bar (incompatible with
    // capacitor-swift-pm 8.0.x). Status bar is styled natively:
    //   Android: styles.xml android:statusBarColor
    //   iOS: Info.plist UIStatusBarStyle + preferredStatusBarStyle
  },
  android: {
    allowMixedContent: true,
  },
  ios: {
    contentInset: 'automatic',
    scheme: 'TrustSky Spotlight',
  },
};

export default config;
