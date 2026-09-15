package ph.elilai.kafe.printer;

import static org.junit.Assert.assertArrayEquals;
import static org.junit.Assert.assertTrue;
import static org.junit.Assert.fail;

import java.io.InputStream;
import java.net.ServerSocket;
import java.net.Socket;
import java.util.Arrays;
import java.util.concurrent.Callable;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.Future;
import java.util.concurrent.TimeUnit;
import org.junit.Test;

public class EscPosTcpClientTest {
    private static final byte[] DRAWER_PIN2 =
            new byte[] {0x1B, 0x70, 0x00, 0x19, (byte) 0xFA};

    @Test
    public void sendDeliversExactPayload() throws Exception {
        try (ServerSocket server = new ServerSocket(0)) {
            int port = server.getLocalPort();
            ExecutorService pool = Executors.newSingleThreadExecutor();
            Future<byte[]> received =
                    pool.submit(
                            (Callable<byte[]>)
                                    () -> {
                                        try (Socket client = server.accept()) {
                                            client.setSoTimeout(2000);
                                            InputStream in = client.getInputStream();
                                            byte[] buffer = new byte[256];
                                            int read = in.read(buffer);
                                            if (read < 0) {
                                                return new byte[0];
                                            }
                                            return Arrays.copyOf(buffer, read);
                                        }
                                    });

            byte[] payload = new byte[] {0x1B, 0x40, 0x48, 0x69, 0x0A};
            EscPosTcpClient.send("127.0.0.1", port, payload, 2000);

            assertArrayEquals(payload, received.get(3, TimeUnit.SECONDS));
            pool.shutdownNow();
        }
    }

    @Test
    public void sendDrawerKickPin2() throws Exception {
        try (ServerSocket server = new ServerSocket(0)) {
            int port = server.getLocalPort();
            ExecutorService pool = Executors.newSingleThreadExecutor();
            Future<byte[]> received =
                    pool.submit(
                            (Callable<byte[]>)
                                    () -> {
                                        try (Socket client = server.accept()) {
                                            client.setSoTimeout(2000);
                                            InputStream in = client.getInputStream();
                                            byte[] buffer = new byte[32];
                                            int read = in.read(buffer);
                                            return Arrays.copyOf(buffer, Math.max(read, 0));
                                        }
                                    });

            EscPosTcpClient.send("127.0.0.1", port, DRAWER_PIN2, 2000);
            assertArrayEquals(DRAWER_PIN2, received.get(3, TimeUnit.SECONDS));
            pool.shutdownNow();
        }
    }

    @Test
    public void connectionFailureSurfacesClearError() {
        try {
            EscPosTcpClient.send("127.0.0.1", 1, new byte[] {0x1B, 0x40}, 500);
            fail("expected IOException");
        } catch (Exception error) {
            assertTrue(error.getMessage().contains("Cannot reach printer"));
        }
    }

    @Test
    public void emptyPayloadRejected() {
        try {
            EscPosTcpClient.send("127.0.0.1", 9100, new byte[0], 500);
            fail("expected IOException");
        } catch (Exception error) {
            assertTrue(error.getMessage().contains("empty"));
        }
    }
}
