package ae.trustsky.spotlight;

import ae.trustsky.spotlight.plugins.OfflineTilesPlugin;
import android.os.Bundle;
import com.getcapacitor.BridgeActivity;

public class MainActivity extends BridgeActivity {

  @Override
  protected void onCreate(Bundle savedInstanceState) {
    registerPlugin(OfflineTilesPlugin.class);
    super.onCreate(savedInstanceState);
  }
}
