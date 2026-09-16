package ph.elilai.kafe;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertTrue;

import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.regex.Matcher;
import java.util.regex.Pattern;
import org.junit.Test;

/**
 * Local Capacitor plugin classpath must be listed for PluginManager discovery so Bridge
 * create-time JSExport includes EscPosPrinter in PluginHeaders / Cap.Plugins.
 */
public class CapacitorPluginsLocalJsonTest {

    private static final String ESCPOS_CLASSPATH =
            "ph.elilai.kafe.printer.EscPosPrinterPlugin";

    @Test
    public void localPluginsJsonListsEscPosPrinterClasspath() throws Exception {
        Path localJson = Path.of("capacitor.plugins.local.json");
        assertTrue("capacitor.plugins.local.json must exist", Files.exists(localJson));

        String body = readUtf8(localJson);
        assertTrue(body.contains(ESCPOS_CLASSPATH));
        assertTrue(body.contains("\"pkg\""));
        assertTrue(body.contains("\"classpath\""));
    }

    @Test
    public void localPluginsJsonIsValidArrayWithEscPosEntry() throws Exception {
        Path localJson = Path.of("capacitor.plugins.local.json");
        String body = readUtf8(localJson).trim();
        assertTrue(body.startsWith("["));
        assertTrue(body.endsWith("]"));

        Matcher classpath =
                Pattern.compile("\"classpath\"\\s*:\\s*\"([^\"]+)\"").matcher(body);
        assertTrue(classpath.find());
        assertEquals(ESCPOS_CLASSPATH, classpath.group(1));
        assertFalse("only the local EscPos entry is expected", classpath.find());
    }

    private static String readUtf8(Path path) throws Exception {
        return new String(Files.readAllBytes(path), StandardCharsets.UTF_8);
    }
}
