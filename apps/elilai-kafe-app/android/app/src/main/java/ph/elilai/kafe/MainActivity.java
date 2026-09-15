package ph.elilai.kafe;

import android.os.Bundle;
import android.webkit.WebView;
import com.getcapacitor.BridgeActivity;
import com.getcapacitor.Logger;
import com.getcapacitor.WebViewListener;
import java.io.BufferedReader;
import java.io.IOException;
import java.io.InputStream;
import java.io.InputStreamReader;
import java.nio.charset.StandardCharsets;
import ph.elilai.kafe.printer.EscPosPrinterPlugin;

public class MainActivity extends BridgeActivity {
    private static final String NATIVE_SHELL_ASSET = "public/js/elilai-native-shell.js";
    private String nativeShellScript;

    @Override
    public void onCreate(Bundle savedInstanceState) {
        registerPlugin(EscPosPrinterPlugin.class);

        // Register before super.onCreate so the first WebView page load cannot miss injection.
        // (Remote server.url never executes www/ as the document.)
        bridgeBuilder.addWebViewListener(
            new WebViewListener() {
                @Override
                public void onPageLoaded(WebView webView) {
                    injectNativeShell(webView);
                }

                @Override
                public void onPageCommitVisible(WebView webView, String url) {
                    // Earlier than onPageLoaded on some devices; shell is idempotent.
                    injectNativeShell(webView);
                }
            }
        );

        super.onCreate(savedInstanceState);

        // Ensure EscPosPrinter is on the live Bridge map (Builder registration alone
        // was insufficient at runtime: Bridge.getPlugin("EscPosPrinter") == null).
        if (this.bridge != null) {
            this.bridge.registerPlugin(EscPosPrinterPlugin.class);
            if (this.bridge.getPlugin("EscPosPrinter") != null) {
                Logger.debug("EscPosPrinter registered on live Bridge");
            } else {
                Logger.error("EscPosPrinter missing from live Bridge after registerPlugin");
            }
            injectNativeShell(this.bridge.getWebView());
        }
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
