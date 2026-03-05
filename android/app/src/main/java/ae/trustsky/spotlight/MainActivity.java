package ae.trustsky.spotlight;

import ae.trustsky.spotlight.plugins.BroadcastRemoteIdPlugin;
import ae.trustsky.spotlight.plugins.OfflineTilesPlugin;
import android.os.Bundle;
import android.view.View;
import androidx.core.view.ViewCompat;
import androidx.core.view.WindowInsetsCompat;
import com.getcapacitor.BridgeActivity;

public class MainActivity extends BridgeActivity {

  @Override
  protected void onCreate(Bundle savedInstanceState) {
    registerPlugin(OfflineTilesPlugin.class);
    registerPlugin(BroadcastRemoteIdPlugin.class);
    super.onCreate(savedInstanceState);

    // Disable edge-to-edge: fit content between status bar and navigation bar.
    View content = findViewById(android.R.id.content);
    ViewCompat.setOnApplyWindowInsetsListener(
        content,
        (v, insets) -> {
          var bars = insets.getInsets(WindowInsetsCompat.Type.systemBars());
          v.setPadding(bars.left, bars.top, bars.right, bars.bottom);
          return WindowInsetsCompat.CONSUMED;
        });
  }
}
