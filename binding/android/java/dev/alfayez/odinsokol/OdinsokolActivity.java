
package dev.alfayez.odinsokol;

import org.libsdl.app.SDLActivity;

public class OdinsokolActivity extends SDLActivity
{
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
