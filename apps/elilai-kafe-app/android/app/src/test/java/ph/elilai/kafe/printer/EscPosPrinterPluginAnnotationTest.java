package ph.elilai.kafe.printer;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertNotNull;
import static org.junit.Assert.assertTrue;

import com.getcapacitor.PluginMethod;
import com.getcapacitor.annotation.CapacitorPlugin;
import java.lang.reflect.Method;
import java.util.Arrays;
import java.util.Set;
import java.util.stream.Collectors;
import org.junit.Test;

/** Registration metadata required for Cap 8.5.2 Bridge / JSExport PluginHeaders. */
public class EscPosPrinterPluginAnnotationTest {

    @Test
    public void capacitorPluginNameIsEscPosPrinter() {
        CapacitorPlugin annotation = EscPosPrinterPlugin.class.getAnnotation(CapacitorPlugin.class);
        assertNotNull("@CapacitorPlugin must be present for Bridge.registerPlugin", annotation);
        assertEquals("EscPosPrinter", annotation.name());
    }

    @Test
    public void pluginMethodsExposeSendAndGetDefaults() {
        Set<String> methods =
                Arrays.stream(EscPosPrinterPlugin.class.getMethods())
                        .filter(method -> method.getAnnotation(PluginMethod.class) != null)
                        .map(Method::getName)
                        .collect(Collectors.toSet());

        assertTrue(methods.contains("send"));
        assertTrue(methods.contains("getDefaults"));
    }

    @Test
    public void pluginClassIsPubliclyConstructible() throws Exception {
        EscPosPrinterPlugin instance =
                EscPosPrinterPlugin.class.getDeclaredConstructor().newInstance();
        assertNotNull(instance);
    }
}
