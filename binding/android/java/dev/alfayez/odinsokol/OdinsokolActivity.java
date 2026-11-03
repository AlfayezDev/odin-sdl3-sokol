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

        // odin -> platform: generated JNI glue calls these callbacks.
        OdinBridge.setPlatform(new OdinBridge.PlatformHandler() {
            @Override
            public void showToast(String message) {
                runOnUiThread(() -> {
                    if (!isFinishing() && !isDestroyed()) {
                        android.widget.Toast.makeText(
                            OdinsokolActivity.this,
                            message,
                            android.widget.Toast.LENGTH_SHORT
                        ).show();
                        android.util.Log.i("OdinNative", "Toast shown on UI thread: " + message);
                    }
                });
            }
        });

        // kotlin -> odin: hello world export call
        android.util.Log.i("OdinBridge", "odin_hello: " + OdinBridge.hello());
        android.util.Log.i("OdinBridge", "odin_add(2, 3) = " + OdinBridge.add(2, 3));
    }

    @Override
    protected void onDestroy() {
        OdinBridge.setPlatform(null);
        super.onDestroy();
    }
}
