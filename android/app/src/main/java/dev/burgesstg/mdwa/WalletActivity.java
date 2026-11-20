package dev.burgesstg.mdwa;

import android.os.Bundle;
import java.util.Arrays;
import java.util.List;
import android.view.WindowManager;
import org.godotengine.godot.GodotActivity;

public final class WalletActivity extends GodotActivity {
    @Override public List<String> getCommandLine() {
        return Arrays.asList("--main-pack", "res://wallet.pck", "--rendering-method", "mobile", "--rendering-driver", "vulkan");
    }

    @Override public void onCreate(Bundle state) {
        getWindow().addFlags(WindowManager.LayoutParams.FLAG_SECURE);
        super.onCreate(state);
    }
}
