package dev.burgesstg.mdwa;

import android.content.Context;
import android.content.Intent;
import android.content.SharedPreferences;
import android.os.Build;
import android.provider.Settings;
import android.security.keystore.KeyGenParameterSpec;
import android.security.keystore.KeyPermanentlyInvalidatedException;
import android.security.keystore.KeyProperties;
import android.util.Base64;
import android.view.HapticFeedbackConstants;
import android.view.View;
import androidx.biometric.BiometricManager;
import androidx.biometric.BiometricPrompt;
import androidx.core.content.ContextCompat;
import androidx.fragment.app.FragmentActivity;
import com.google.mlkit.vision.barcode.common.Barcode;
import com.google.mlkit.vision.codescanner.GmsBarcodeScannerOptions;
import com.google.mlkit.vision.codescanner.GmsBarcodeScanning;
import java.nio.charset.StandardCharsets;
import java.security.KeyStore;
import java.util.function.Consumer;
import javax.crypto.Cipher;
import javax.crypto.KeyGenerator;
import javax.crypto.SecretKey;
import javax.crypto.spec.GCMParameterSpec;
import org.json.JSONObject;

/**
 * Phone features the wallet UI asks for: biometric unlock, haptics, the share
 * sheet and QR scanning.
 *
 * Biometric unlock stores the wallet password encrypted with an AES key in the
 * Android Keystore. The key needs a strong biometric for every use and is
 * invalidated when a fingerprint or face is enrolled, so a new enrolment
 * cannot read the password. The password never leaves the app; the worker
 * opens the vault with it exactly as it does with a typed password.
 */
final class WalletDevice {
    private static final String STORE = "AndroidKeyStore";
    private static final String PREFS = "atom_biometric";
    private static final int STRONG = BiometricManager.Authenticators.BIOMETRIC_STRONG;
    private final FragmentActivity activity;
    private final Consumer<String> emit;

    WalletDevice(FragmentActivity activity, Consumer<String> emit) {
        this.activity = activity;
        this.emit = emit;
    }

    private SharedPreferences prefs() { return activity.getSharedPreferences(PREFS, Context.MODE_PRIVATE); }
    private static String alias(String network) { return "atom.unlock." + network; }

    private void event(String name, String key, String value) {
        try {
            JSONObject o = new JSONObject().put("type", "biometric").put("event", name);
            if (key != null) o.put(key, value);
            emit.accept(o.toString());
        } catch (org.json.JSONException ignored) { /* Fixed keys. */ }
    }

    boolean available() {
        return BiometricManager.from(activity).canAuthenticate(STRONG) == BiometricManager.BIOMETRIC_SUCCESS;
    }

    String status(String network) {
        boolean enabled = prefs().contains(network + ".data") && available();
        return "{\"available\":" + available() + ",\"enabled\":" + enabled + "}";
    }

    private SecretKey key(String network, boolean create) throws Exception {
        KeyStore ks = KeyStore.getInstance(STORE);
        ks.load(null);
        if (!create && ks.containsAlias(alias(network))) return (SecretKey) ks.getKey(alias(network), null);
        KeyGenerator gen = KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, STORE);
        KeyGenParameterSpec.Builder spec = new KeyGenParameterSpec.Builder(alias(network),
                KeyProperties.PURPOSE_ENCRYPT | KeyProperties.PURPOSE_DECRYPT)
            .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
            .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
            .setKeySize(256)
            .setUserAuthenticationRequired(true)
            .setInvalidatedByBiometricEnrollment(true);
        if (Build.VERSION.SDK_INT >= 30) spec.setUserAuthenticationParameters(0, KeyProperties.AUTH_BIOMETRIC_STRONG);
        gen.init(spec.build());
        return gen.generateKey();
    }

    void disable(String network) {
        prefs().edit().remove(network + ".data").remove(network + ".iv").apply();
        try {
            KeyStore ks = KeyStore.getInstance(STORE);
            ks.load(null);
            ks.deleteEntry(alias(network));
        } catch (Exception ignored) { /* Nothing to delete. */ }
    }

    private BiometricPrompt.PromptInfo prompt(String title) {
        return new BiometricPrompt.PromptInfo.Builder()
            .setTitle(title)
            .setSubtitle("Atom Wallet")
            .setNegativeButtonText("Use password")
            .setAllowedAuthenticators(STRONG)
            .build();
    }

    private void authenticate(Cipher cipher, String title, Consumer<Cipher> done) {
        BiometricPrompt p = new BiometricPrompt(activity, ContextCompat.getMainExecutor(activity),
            new BiometricPrompt.AuthenticationCallback() {
                @Override public void onAuthenticationSucceeded(BiometricPrompt.AuthenticationResult result) {
                    done.accept(result.getCryptoObject().getCipher());
                }
                @Override public void onAuthenticationError(int code, CharSequence message) {
                    boolean quiet = code == BiometricPrompt.ERROR_NEGATIVE_BUTTON || code == BiometricPrompt.ERROR_USER_CANCELED
                        || code == BiometricPrompt.ERROR_CANCELED;
                    event("error", "message", quiet ? "" : message.toString());
                }
            });
        p.authenticate(prompt(title), new BiometricPrompt.CryptoObject(cipher));
    }

    void enable(String network, String password) {
        try {
            Cipher cipher = Cipher.getInstance("AES/GCM/NoPadding");
            cipher.init(Cipher.ENCRYPT_MODE, key(network, true));
            authenticate(cipher, "Turn on biometric unlock", c -> {
                try {
                    byte[] data = c.doFinal(password.getBytes(StandardCharsets.UTF_8));
                    prefs().edit()
                        .putString(network + ".data", Base64.encodeToString(data, Base64.NO_WRAP))
                        .putString(network + ".iv", Base64.encodeToString(c.getIV(), Base64.NO_WRAP))
                        .apply();
                    event("enabled", null, null);
                } catch (Exception e) { disable(network); event("error", "message", "Biometric unlock could not be turned on"); }
            });
        } catch (Exception e) {
            disable(network);
            event("error", "message", "Biometric unlock is not available on this phone");
        }
    }

    void unlock(String network) {
        String data = prefs().getString(network + ".data", null);
        String iv = prefs().getString(network + ".iv", null);
        if (data == null || iv == null) { event("error", "message", ""); return; }
        try {
            Cipher cipher = Cipher.getInstance("AES/GCM/NoPadding");
            cipher.init(Cipher.DECRYPT_MODE, key(network, false), new GCMParameterSpec(128, Base64.decode(iv, Base64.NO_WRAP)));
            authenticate(cipher, "Unlock Atom Wallet", c -> {
                try {
                    String password = new String(c.doFinal(Base64.decode(data, Base64.NO_WRAP)), StandardCharsets.UTF_8);
                    event("password", "password", password);
                } catch (Exception e) { disable(network); event("error", "message", "Use your password, then turn biometric unlock on again"); }
            });
        } catch (KeyPermanentlyInvalidatedException e) {
            disable(network);
            event("error", "message", "Biometrics changed on this phone. Unlock with your password and turn biometric unlock on again.");
        } catch (Exception e) {
            event("error", "message", "Use your password to unlock");
        }
    }

    void haptic(View view, String kind) {
        if (view == null) return;
        int effect;
        switch (kind) {
            case "tick": effect = Build.VERSION.SDK_INT >= 21 ? HapticFeedbackConstants.CLOCK_TICK : HapticFeedbackConstants.KEYBOARD_TAP; break;
            case "confirm": case "success": effect = Build.VERSION.SDK_INT >= 30 ? HapticFeedbackConstants.CONFIRM : HapticFeedbackConstants.LONG_PRESS; break;
            case "error": effect = Build.VERSION.SDK_INT >= 30 ? HapticFeedbackConstants.REJECT : HapticFeedbackConstants.LONG_PRESS; break;
            default: effect = HapticFeedbackConstants.VIRTUAL_KEY;
        }
        view.performHapticFeedback(effect);
    }

    void share(String text) {
        Intent send = new Intent(Intent.ACTION_SEND).setType("text/plain").putExtra(Intent.EXTRA_TEXT, text);
        activity.startActivity(Intent.createChooser(send, "Share address"));
    }

    void scan() {
        GmsBarcodeScannerOptions options = new GmsBarcodeScannerOptions.Builder()
            .setBarcodeFormats(Barcode.FORMAT_QR_CODE).enableAutoZoom().build();
        GmsBarcodeScanning.getClient(activity, options).startScan()
            .addOnSuccessListener(code -> emit.accept(json("value", code.getRawValue())))
            .addOnCanceledListener(() -> { })
            .addOnFailureListener(e -> emit.accept(json("error", "The QR scanner needs Google Play services")));
    }

    private static String json(String key, String value) {
        try { return new JSONObject().put("type", "scan").put(key, value == null ? "" : value).toString(); }
        catch (org.json.JSONException e) { return "{\"type\":\"scan\"}"; }
    }

    /** Android's animator duration scale; 0 turns animations off. */
    float motion() {
        return Settings.Global.getFloat(activity.getContentResolver(), Settings.Global.ANIMATOR_DURATION_SCALE, 1f);
    }
}
