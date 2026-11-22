package dev.burgesstg.mdwa;

import android.app.Activity;
import android.net.Uri;
import android.net.http.HttpResponseCache;
import android.os.Handler;
import android.os.Looper;
import android.view.View;
import android.view.ViewGroup;
import android.webkit.RenderProcessGoneDetail;
import android.webkit.WebMessage;
import android.webkit.WebMessagePort;
import android.webkit.WebResourceRequest;
import android.webkit.WebResourceResponse;
import android.webkit.WebView;
import android.webkit.WebViewClient;
import android.widget.FrameLayout;
import org.godotengine.godot.Godot;
import org.godotengine.godot.plugin.GodotPlugin;
import org.godotengine.godot.plugin.SignalInfo;
import org.godotengine.godot.plugin.UsedByGodot;
import java.io.ByteArrayInputStream;
import java.io.File;
import java.io.IOException;
import java.io.FilterInputStream;
import java.net.ResponseCache;
import java.net.URL;
import javax.net.ssl.HttpsURLConnection;
import java.io.InputStream;
import java.util.Collections;
import java.util.Set;

public final class WalletEngine extends GodotPlugin {
    private static final Uri ORIGIN = Uri.parse("https://appassets.androidplatform.net");
    private static final String PAGE = ORIGIN + "/index.html";
    private WebView engineView;
    private volatile WalletExplorer explorer;
    private WebMessagePort requests;
    private NativeProver prover;
    private boolean active = true;
    private boolean started;
    private final Handler main = new Handler(Looper.getMainLooper());
    private final Runnable bootTimeout = () -> emitSignal("message",
        "{\"type\":\"slow\",\"message\":\"The wallet engine is still starting. You can keep waiting or retry.\"}");


    public WalletEngine(Godot godot) { super(godot); }
    @Override public String getPluginName() { return "WalletEngine"; }
    @Override public Set<SignalInfo> getPluginSignals() {
        return Collections.singleton(new SignalInfo("message", String.class));
    }

    private View observedWindow;
    private final android.graphics.Point lastViewport = new android.graphics.Point();
    private final android.graphics.Rect lastInsets = new android.graphics.Rect(-1, -1, -1, -1);
    private final android.view.ViewTreeObserver.OnGlobalLayoutListener layoutListener = this::publishInsets;

    private void observeWindow() {
        Activity activity = getActivity();
        if (activity == null) return;
        if (observedWindow == null) {
            observedWindow = activity.getWindow().getDecorView();
            observedWindow.getViewTreeObserver().addOnGlobalLayoutListener(layoutListener);
        }
        publishInsets();
    }

    private void publishInsets() {
        if (observedWindow == null || getGodot().getRenderView() == null) return;
        View surface = getGodot().getRenderView().getView();
        androidx.core.view.WindowInsetsCompat root = androidx.core.view.ViewCompat.getRootWindowInsets(observedWindow);
        if (root == null || surface == null || surface.getWidth() == 0) return;
        androidx.core.graphics.Insets edges = root.getInsets(androidx.core.view.WindowInsetsCompat.Type.systemBars()
            | androidx.core.view.WindowInsetsCompat.Type.displayCutout() | androidx.core.view.WindowInsetsCompat.Type.ime());
        int[] window = new int[2], view = new int[2];
        observedWindow.getLocationOnScreen(window);
        surface.getLocationOnScreen(view);
        int left = Math.max(0, window[0] + edges.left - view[0]);
        int top = Math.max(0, window[1] + edges.top - view[1]);
        int right = Math.max(0, view[0] + surface.getWidth() - (window[0] + observedWindow.getWidth() - edges.right));
        int bottom = Math.max(0, view[1] + surface.getHeight() - (window[1] + observedWindow.getHeight() - edges.bottom));
        float density = surface.getResources().getDisplayMetrics().density;
        int widthDp = Math.round(surface.getWidth() / density);
        int heightDp = Math.round(surface.getHeight() / density);
        if (lastViewport.x == widthDp && lastViewport.y == heightDp && lastInsets.left == left
                && lastInsets.top == top && lastInsets.right == right && lastInsets.bottom == bottom) return;
        lastViewport.set(widthDp, heightDp);
        lastInsets.set(left, top, right, bottom);
        emitSignal("message", "{\"type\":\"insets\",\"edges\":[" + left + "," + top + "," + right + "," + bottom
            + "],\"widthDp\":" + widthDp + ",\"heightDp\":" + heightDp + ",\"motion\":" + device().motion() + "}");
    }

    @UsedByGodot public void startEngine() {
        runOnHostThread(() -> {
            started = true;
            observeWindow();
            if (active && engineView == null) open();
        });
    }

    @UsedByGodot public void request(String json) {
        runOnHostThread(() -> {
            if (requests != null) requests.postMessage(new WebMessage(json));
        });
    }

    private static synchronized void enableMaterialCache(File directory) {
        if (ResponseCache.getDefault() != null) return;
        try {
            HttpResponseCache.install(new File(directory, "prover-http"), 64L * 1024 * 1024);
        } catch (IOException ignored) { /* Material can still be fetched directly. */ }
    }

    // WebView cannot read the public SRS host cross-origin. Publish just
    // these static files under our private origin. The SDK verifies each hash.
    private WebResourceResponse publicMaterial(String name) {
        HttpsURLConnection connection = null;
        try {
            connection = (HttpsURLConnection) new URL("https://srs.midnight.network/" + name).openConnection();
            connection.setInstanceFollowRedirects(false);
            connection.setConnectTimeout(15000);
            connection.setReadTimeout(60000);
            int status = connection.getResponseCode();
            if (status != 200) {
                connection.disconnect();
                return new WebResourceResponse("text/plain", "utf-8", status == 404 ? 404 : 502,
                    "Circuit material unavailable", Collections.emptyMap(), new ByteArrayInputStream(new byte[0]));
            }
            final HttpsURLConnection upstream = connection;
            InputStream stream = new FilterInputStream(connection.getInputStream()) {
                @Override public void close() throws IOException {
                    try { super.close(); } finally { upstream.disconnect(); }
                }
            };
            return new WebResourceResponse("application/octet-stream", null, stream);
        } catch (IOException unavailable) {
            if (connection != null) connection.disconnect();
            return new WebResourceResponse("text/plain", "utf-8", 502, "Circuit material unavailable",
                Collections.emptyMap(), new ByteArrayInputStream(new byte[0]));
        }
    }

    private void open() {
        Activity activity = getActivity();
        if (activity == null) return;
        main.postDelayed(bootTimeout, 60000);
        WebView view = new WebView(activity);
        engineView = view;
        view.getSettings().setJavaScriptEnabled(true);
        view.getSettings().setDomStorageEnabled(true);
        view.getSettings().setAllowFileAccess(false);
        view.getSettings().setAllowContentAccess(false);
        view.setImportantForAccessibility(View.IMPORTANT_FOR_ACCESSIBILITY_NO_HIDE_DESCENDANTS);
        view.setFocusable(false);
        view.setWebViewClient(new WebViewClient() {
            @Override public boolean shouldOverrideUrlLoading(WebView v, WebResourceRequest r) { return true; }

            @Override public WebResourceResponse shouldInterceptRequest(WebView v, WebResourceRequest r) {
                Uri url = r.getUrl();
                if (!ORIGIN.getHost().equals(url.getHost())) return null;
                String path = url.getPath();
                if ("https".equals(url.getScheme()) && path != null && path.matches("/[A-Za-z0-9_./-]+") && !path.contains("..")) {
                    if ("GET".equals(r.getMethod()) && path.startsWith("/prover-material/")) {
                        String name = path.substring("/prover-material/".length());
                        if (name.matches("bls_midnight_2p[0-9]{1,2}|(zswap|dust)/(9|10)/(spend|output|sign)[.](prover|verifier|bzkir)")) {
                            enableMaterialCache(activity.getCodeCacheDir());
                            return publicMaterial(name);
                        }
                    }
                    try {
                        InputStream file = activity.getAssets().open("engine" + path);
                        String mime = path.endsWith(".wasm") ? "application/wasm"
                            : (path.endsWith(".js") || path.endsWith(".mjs")) ? "application/javascript" : path.endsWith(".json") ? "application/json"
                            : path.endsWith(".html") ? "text/html" : "application/octet-stream";
                        return new WebResourceResponse(mime, null, file);
                    } catch (IOException ignored) { /* Return a local 404. */ }
                }
                return new WebResourceResponse("text/plain", "utf-8", 404, "Missing", Collections.emptyMap(),
                    new ByteArrayInputStream(new byte[0]));
            }

            @Override public void onPageFinished(WebView v, String url) {
                if (engineView != v || requests != null || !PAGE.equals(url)) return;
                WebMessagePort[] pair = v.createWebMessageChannel();
                WebMessagePort[] proofs = v.createWebMessageChannel();
                prover = new NativeProver(proofs[0]);
                requests = pair[0];
                requests.setWebMessageCallback(new WebMessagePort.WebMessageCallback() {
                    private boolean connected;

                    // Replies keep flowing while the app is in the background, so a
                    // transaction that finishes there is not lost to the UI.
                    @Override public void onMessage(WebMessagePort port, WebMessage message) {
                        String data = message.getData();
                        if (engineView != v || data == null) return;
                        boolean state = data.startsWith("{\"type\":\"state\"");
                        if (state && !connected) {
                            connected = true;
                            android.util.Log.i("MDWA", "Wallet worker ready");
                        }
                        main.removeCallbacks(bootTimeout);
                        emitSignal("message", data);
                        // JSON escapes quotes inside strings, so this text is only ever the idle busy slot.
                        boolean now = state ? !data.contains("\"busy\":null") : transacting;
                        if (now == transacting) return;
                        transacting = now;
                        if (!active) {
                            main.removeCallbacks(lockNow);
                            main.postDelayed(lockNow, Math.max(0, lockWait()));
                        }
                    }
                });
                v.postWebMessage(new WebMessage("connect", new WebMessagePort[]{pair[1], proofs[1]}), ORIGIN);
            }

            @Override public boolean onRenderProcessGone(WebView v, RenderProcessGoneDetail detail) {
                if (engineView == v) {
                    close();
                    emitSignal("message", "{\"type\":\"fatal\",\"message\":\"The wallet engine stopped. Reopen it to unlock your wallet.\"}");
                }
                return true;
            }
        });
        FrameLayout content = activity.findViewById(android.R.id.content);
        content.addView(view, 0, new FrameLayout.LayoutParams(1, 1));
        view.loadUrl(PAGE);
    }

    @UsedByGodot public void showExplorer(String url, int x, int y, int width, int height) {
        runOnHostThread(() -> {
            if (!active || getActivity() == null || getGodot().getRenderView() == null) return;
            if (explorer == null) explorer = new WalletExplorer(getActivity(), msg -> emitSignal("message", msg));
            explorer.show(url, getGodot().getRenderView().getView(), x, y, width, height);
        });
    }
    @UsedByGodot public void hideExplorer() { runOnHostThread(() -> { if (explorer != null) explorer.hide(); }); }
    @UsedByGodot public void closeExplorer() { runOnHostThread(() -> { if (explorer != null) explorer.close(); }); }
    @UsedByGodot public void reloadExplorer() { runOnHostThread(() -> { if (explorer != null) explorer.reload(); }); }
    @UsedByGodot public void explorerForward() { runOnHostThread(() -> { if (explorer != null) explorer.forward(); }); }
    @UsedByGodot public boolean explorerBack() {
        if (explorer == null || !explorer.canGoBack()) return false;
        runOnHostThread(() -> { if (explorer != null) explorer.back(); });
        return true;
    }

    private WalletDevice device;
    private WalletDevice device() {
        if (device == null) device = new WalletDevice((androidx.fragment.app.FragmentActivity) getActivity(), msg -> emitSignal("message", msg));
        return device;
    }
    private View surface() { return getGodot().getRenderView() == null ? null : getGodot().getRenderView().getView(); }

    @UsedByGodot public String biometricStatus(String network) { return getActivity() == null ? "{}" : device().status(network); }
    @UsedByGodot public void enableBiometric(String network, String password) { runOnHostThread(() -> device().enable(network, password)); }
    @UsedByGodot public void disableBiometric(String network) { runOnHostThread(() -> device().disable(network)); }
    @UsedByGodot public void unlockWithBiometric(String network) { runOnHostThread(() -> device().unlock(network)); }
    @UsedByGodot public void haptic(String kind) { runOnHostThread(() -> device().haptic(surface(), kind)); }
    @UsedByGodot public void share(String text) { runOnHostThread(() -> device().share(text)); }
    @UsedByGodot public void scanQr() { runOnHostThread(() -> device().scan()); }

    // Seconds the worker stays unlocked after the app leaves the screen.
    private volatile int autoLockSeconds;
    // A transaction that is proving or submitting gets this long to finish in the background.
    private static final long TRANSACTION_GRACE_MS = 3 * 60 * 1000L;
    private boolean transacting;
    private long pausedAt;
    private long lockWait() {
        long keep = Math.max(autoLockSeconds * 1000L, transacting ? TRANSACTION_GRACE_MS : 0);
        return keep - (android.os.SystemClock.elapsedRealtime() - pausedAt);
    }
    private final Runnable lockNow = () -> {
        if (active) return;
        close();
        emitSignal("message", "{\"type\":\"closed\"}");
    };
    @UsedByGodot public void setAutoLock(int seconds) { autoLockSeconds = Math.max(0, Math.min(seconds, 600)); }

    @UsedByGodot public void retryEngine() {
        runOnHostThread(() -> {
            if (!active) return;
            close();
            open();
        });
    }

    private void close() {
        if (explorer != null) explorer.close();
        main.removeCallbacks(bootTimeout);
        if (requests != null) requests.close();
        requests = null;
        if (prover != null) prover.close();
        prover = null;
        transacting = false;
        if (engineView == null) return;
        WebView view = engineView;
        engineView = null;
        if (view.getParent() instanceof ViewGroup) ((ViewGroup) view.getParent()).removeView(view);
        view.destroy();
    }

    // Ending the worker drops all in-memory keys. With an auto-lock delay, or
    // while a transaction is in flight, the worker keeps running in the
    // background until the delay passes.
    @Override public void onMainPause() {
        active = false;
        pausedAt = android.os.SystemClock.elapsedRealtime();
        main.removeCallbacks(lockNow);
        long wait = lockWait();
        if (wait <= 0) lockNow.run();
        else main.postDelayed(lockNow, wait);
    }
    @Override public void onMainResume() {
        main.removeCallbacks(lockNow);
        active = true;
        if (started && engineView == null) open();
    }
    @Override public void onMainDestroy() {
        if (observedWindow != null && observedWindow.getViewTreeObserver().isAlive())
            observedWindow.getViewTreeObserver().removeOnGlobalLayoutListener(layoutListener);
        observedWindow = null;
        close();
    }
}
