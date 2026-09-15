package ph.elilai.kafe.printer;

import android.util.Base64;
import com.getcapacitor.JSObject;
import com.getcapacitor.Plugin;
import com.getcapacitor.PluginCall;
import com.getcapacitor.PluginMethod;
import com.getcapacitor.annotation.CapacitorPlugin;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

/**
 * Capacitor bridge: WebView → raw ESC/POS TCP on shop LAN.
 * Phoenix never opens the printer socket.
 */
@CapacitorPlugin(name = "EscPosPrinter")
public class EscPosPrinterPlugin extends Plugin {
    private final ExecutorService executor = Executors.newSingleThreadExecutor();

    @PluginMethod
    public void send(PluginCall call) {
        String dataBase64 = call.getString("dataBase64");
        if (dataBase64 == null || dataBase64.trim().isEmpty()) {
            call.reject("Missing dataBase64 ESC/POS payload");
            return;
        }

        final String host =
                optionalString(call.getString("host"), EscPosTcpClient.DEFAULT_HOST);
        final int port = call.getInt("port", EscPosTcpClient.DEFAULT_PORT);
        final int timeoutMs = call.getInt("timeoutMs", EscPosTcpClient.DEFAULT_TIMEOUT_MS);

        final byte[] payload;
        try {
            payload = Base64.decode(dataBase64, Base64.DEFAULT);
        } catch (IllegalArgumentException error) {
            call.reject("Invalid dataBase64 payload");
            return;
        }

        if (payload.length == 0) {
            call.reject("Decoded ESC/POS payload is empty");
            return;
        }

        executor.execute(
                () -> {
                    try {
                        EscPosTcpClient.send(host, port, payload, timeoutMs);
                        JSObject result = new JSObject();
                        result.put("ok", true);
                        result.put("host", host);
                        result.put("port", port);
                        result.put("bytes", payload.length);
                        call.resolve(result);
                    } catch (Exception error) {
                        call.reject(error.getMessage() != null ? error.getMessage() : "Printer send failed");
                    }
                });
    }

    @PluginMethod
    public void getDefaults(PluginCall call) {
        JSObject result = new JSObject();
        result.put("host", EscPosTcpClient.DEFAULT_HOST);
        result.put("port", EscPosTcpClient.DEFAULT_PORT);
        result.put("timeoutMs", EscPosTcpClient.DEFAULT_TIMEOUT_MS);
        call.resolve(result);
    }

    private static String optionalString(String value, String fallback) {
        if (value == null) {
            return fallback;
        }
        String trimmed = value.trim();
        return trimmed.isEmpty() ? fallback : trimmed;
    }

    @Override
    protected void handleOnDestroy() {
        executor.shutdownNow();
        super.handleOnDestroy();
    }
}
