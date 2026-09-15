package ph.elilai.kafe.printer;

import java.io.IOException;
import java.io.OutputStream;
import java.net.InetSocketAddress;
import java.net.Socket;
import java.net.SocketTimeoutException;

/**
 * Raw TCP sender for LAN ESC/POS printers (HS-802UL :9100).
 * Must not run on the Android main thread.
 */
public final class EscPosTcpClient {
    public static final String DEFAULT_HOST = "192.168.0.87";
    public static final int DEFAULT_PORT = 9100;
    public static final int DEFAULT_TIMEOUT_MS = 4000;

    private EscPosTcpClient() {}

    public static void send(String host, int port, byte[] payload, int timeoutMs)
            throws IOException {
        if (host == null || host.trim().isEmpty()) {
            throw new IOException("Printer host is not configured");
        }
        if (payload == null || payload.length == 0) {
            throw new IOException("Printer payload is empty");
        }
        if (port <= 0 || port > 65535) {
            throw new IOException("Invalid printer port: " + port);
        }
        if (timeoutMs <= 0) {
            timeoutMs = DEFAULT_TIMEOUT_MS;
        }

        Socket socket = new Socket();
        try {
            socket.connect(new InetSocketAddress(host.trim(), port), timeoutMs);
            socket.setSoTimeout(timeoutMs);
            OutputStream out = socket.getOutputStream();
            out.write(payload);
            out.flush();
            try {
                Thread.sleep(150);
            } catch (InterruptedException interrupted) {
                Thread.currentThread().interrupt();
            }
        } catch (SocketTimeoutException timeout) {
            throw new IOException(
                    "Printer timed out at " + host + ":" + port + " — check shop Wi‑Fi and printer power",
                    timeout);
        } catch (IOException io) {
            throw new IOException(
                    "Cannot reach printer at " + host + ":" + port + " — join main shop Wi‑Fi (" + io.getMessage() + ")",
                    io);
        } finally {
            try {
                socket.close();
            } catch (IOException ignored) {
                // best-effort cleanup
            }
        }
    }
}
