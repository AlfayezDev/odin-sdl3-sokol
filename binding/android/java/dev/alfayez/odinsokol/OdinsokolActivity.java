
package dev.alfayez.odinsokol;

import android.os.Bundle;
import org.libsdl.app.SDLActivity;

public class OdinsokolActivity extends SDLActivity
{
    static {
        // loads bridge_jni's JNI_OnLoad (caches the JavaVM) before any
        // OdinBridge external call; SDL also loads this lib later (no-op).
        System.loadLibrary("main");
    }

    @Override
    public void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        OdinBridge.activity = this;
        // kotlin -> odin: hello world export call
        android.util.Log.i("OdinBridge", "odin_hello: " + OdinBridge.hello());
        android.util.Log.i("OdinBridge", "odin_add(2, 3) = " + OdinBridge.add(2, 3));
    }

    // Standard UTF-8 bytes avoid JNI modified-UTF-8 limitations (including emoji).
    public void showOdinToast(byte[] utf8) {
        final String message = new String(utf8, java.nio.charset.StandardCharsets.UTF_8);
        runOnUiThread(() -> {
            if (!isFinishing() && !isDestroyed()) {
                android.widget.Toast.makeText(this, message, android.widget.Toast.LENGTH_SHORT).show();
                android.util.Log.i("OdinNative", "Toast shown on UI thread: " + message);
            }
        });
    }
}
