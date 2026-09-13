package ph.elilai.kafe;

import android.os.Bundle;
import android.webkit.WebView;
import com.getcapacitor.BridgeActivity;
import com.getcapacitor.WebViewListener;
import java.io.BufferedReader;
import java.io.IOException;
import java.io.InputStream;
import java.io.InputStreamReader;
import java.nio.charset.StandardCharsets;

public class MainActivity extends BridgeActivity {
    private static final String NATIVE_SHELL_ASSET = "public/js/elilai-native-shell.js";
    private String nativeShellScript;

    @Override
    public void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);

        // Remote server.url never executes www/ as the document. Inject the
        // Android back handler after each full WebView document load.
        this.bridge.addWebViewListener(
            new WebViewListener() {
                @Override
                public void onPageLoaded(WebView webView) {
                    injectNativeShell(webView);
                }
            }
        );
    }

    private void injectNativeShell(WebView webView) {
        if (webView == null) {
            return;
        }

        String script = loadNativeShellScript();
        if (script == null || script.isEmpty()) {
            return;
        }

        webView.evaluateJavascript(script, null);
    }

    private String loadNativeShellScript() {
        if (nativeShellScript != null) {
            return nativeShellScript;
        }

        try (InputStream input = getAssets().open(NATIVE_SHELL_ASSET);
             BufferedReader reader =
                 new BufferedReader(new InputStreamReader(input, StandardCharsets.UTF_8))) {
            StringBuilder builder = new StringBuilder();
            String line;
            while ((line = reader.readLine()) != null) {
                builder.append(line).append('\n');
            }
            nativeShellScript = builder.toString();
            return nativeShellScript;
        } catch (IOException error) {
            return null;
        }
    }
}
