package dev.burgesstg.mdwa;

import android.app.Activity;
import android.net.Uri;
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
import java.io.IOException;
import java.io.FilterInputStream;
import java.net.URL;
import javax.net.ssl.HttpsURLConnection;
import java.io.InputStream;
import java.util.Collections;
import java.util.Set;

public final class WalletEngine extends GodotPlugin {
    private static final Uri ORIGIN = Uri.parse("https://appassets.androidplatform.net");
    private static final String PAGE = ORIGIN + "/index.html";
    private WebView engineView;
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

    @UsedByGodot public void startEngine() {
        runOnHostThread(() -> {
            started = true;
            if (active && engineView == null) open();
        });
    }

    @UsedByGodot public void request(String json) {
        runOnHostThread(() -> {
            if (requests != null && active) requests.postMessage(new WebMessage(json));
        });
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
                        if (name.matches("bls_midnight_2p[0-9]{1,2}|(zswap|dust)/(9|10)/(spend|output|sign)[.](prover|verifier|bzkir)"))
                            return publicMaterial(name);
                    }
                    try {
                        InputStream file = activity.getAssets().open("engine" + path);
                        String mime = path.endsWith(".wasm") ? "application/wasm"
                            : (path.endsWith(".js") || path.endsWith(".mjs")) ? "application/javascript" : "text/html";
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

                    @Override public void onMessage(WebMessagePort port, WebMessage message) {
                        if (!active || engineView != v || message.getData() == null) return;
                        if (!connected && message.getData().startsWith("{\"type\":\"state\"")) {
                            connected = true;
                            android.util.Log.i("MDWA", "Wallet worker ready");
                        }
                        main.removeCallbacks(bootTimeout);
                        emitSignal("message", message.getData());
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

    @UsedByGodot public void retryEngine() {
        runOnHostThread(() -> {
            if (!active) return;
            close();
            open();
        });
    }

    private void close() {
        main.removeCallbacks(bootTimeout);
        if (requests != null) requests.close();
        requests = null;
        if (prover != null) prover.close();
        prover = null;
        if (engineView == null) return;
        WebView view = engineView;
        engineView = null;
        if (view.getParent() instanceof ViewGroup) ((ViewGroup) view.getParent()).removeView(view);
        view.destroy();
    }

    // Ending the worker drops all in-memory keys. The encrypted vault survives.
    @Override public void onMainPause() {
        active = false;
        close();
        emitSignal("message", "{\"type\":\"closed\"}");
    }
    @Override public void onMainResume() {
        active = true;
        if (started && engineView == null) open();
    }
    @Override public void onMainDestroy() { close(); }
}
