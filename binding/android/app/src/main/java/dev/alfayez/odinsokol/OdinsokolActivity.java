package dev.alfayez.odinsokol;

import android.os.Bundle;
import android.util.Log;
import android.widget.Toast;
import org.libsdl.app.SDLActivity;

public class OdinsokolActivity extends SDLActivity {
    private static final String TAG = "OdinBridge";

    static {
        System.loadLibrary("main");
    }

    @Override
    public void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);

        OdinBridge.setPlatform(new OdinBridge.PlatformHandler() {
            @Override
            public void showToast(String message) {
                if (!isFinishing() && !isDestroyed()) {
                    Toast.makeText(OdinsokolActivity.this, message, Toast.LENGTH_SHORT).show();
                    Log.i(TAG, message);
                }
            }
        });

        Log.i(TAG, "hello: " + OdinBridge.hello());
    }

    @Override
    protected void onDestroy() {
        OdinBridge.setPlatform(null);
        super.onDestroy();
    }
}
