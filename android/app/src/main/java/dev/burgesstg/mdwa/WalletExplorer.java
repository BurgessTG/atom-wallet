package dev.burgesstg.mdwa;

import android.app.Activity;
import android.graphics.Bitmap;
import android.graphics.Color;
import android.net.Uri;
import android.net.http.SslError;
import android.view.Gravity;
import android.view.View;
import android.view.ViewGroup;
import android.webkit.RenderProcessGoneDetail;
import android.webkit.SslErrorHandler;
import android.webkit.WebChromeClient;
import android.webkit.WebResourceRequest;
import android.webkit.WebResourceResponse;
import android.webkit.WebView;
import android.webkit.WebViewClient;
import android.widget.FrameLayout;
import java.io.ByteArrayInputStream;
import java.util.Collections;
import java.util.function.Consumer;
import org.json.JSONException;
import org.json.JSONObject;

/**
 * The Explore browser: any HTTPS site, in its own view. It has no wallet
 * message port, and it can never load the wallet engine's origin, so a page
 * cannot run script where the vault is stored. Camera, microphone, location,
 * file access and downloads stay off.
 */
final class WalletExplorer {
    private static final String ENGINE_HOST = "appassets.androidplatform.net";
    private final Activity activity;
    private final FrameLayout host;
    private final Consumer<String> notify;
    private WebView page;
    private String current = "";
    private String title = "";
    private boolean loading;
    private int progress;
    private volatile boolean canGoBack;

    WalletExplorer(Activity activity, Consumer<String> notify) {
        this.activity = activity;
        this.notify = notify;
        host = activity.findViewById(android.R.id.content);
    }

    private static boolean allowed(Uri uri) {
        return "https".equals(uri.getScheme()) && uri.getHost() != null && !uri.getHost().isEmpty()
            && uri.getUserInfo() == null && !ENGINE_HOST.equalsIgnoreCase(uri.getHost());
    }

    private static WebResourceResponse missing() {
        return new WebResourceResponse("text/plain", "UTF-8", 404, "Missing",
            Collections.emptyMap(), new ByteArrayInputStream(new byte[0]));
    }

    /** Tells the UI where the browser is; `notice` is a short message for the user. */
    private void publish(String notice) {
        if (page == null) return;
        canGoBack = page.canGoBack();
        try {
            JSONObject o = new JSONObject().put("type", "browser").put("url", current).put("title", title)
                .put("loading", loading).put("progress", progress)
                .put("back", canGoBack).put("forward", page.canGoForward());
            if (notice != null) o.put("notice", notice);
            notify.accept(o.toString());
        } catch (JSONException ignored) { /* Fixed keys. */ }
    }

    private void create() {
        page = new WebView(activity);
        page.setBackgroundColor(Color.rgb(11, 11, 20));
        page.getSettings().setAllowFileAccess(false);
        page.getSettings().setAllowContentAccess(false);
        page.getSettings().setJavaScriptEnabled(true);
        page.getSettings().setDomStorageEnabled(true);
        page.getSettings().setUseWideViewPort(true);
        page.getSettings().setLoadWithOverviewMode(true);
        page.getSettings().setBuiltInZoomControls(true);
        page.getSettings().setDisplayZoomControls(false);
        page.getSettings().setGeolocationEnabled(false);
        page.setWebViewClient(new WebViewClient() {
            @Override public boolean shouldOverrideUrlLoading(WebView view, WebResourceRequest req) {
                Uri uri = req.getUrl();
                if (allowed(uri)) return false;
                if (!req.isForMainFrame()) return true;
                // Plain HTTP is off for the whole app: try the same address over HTTPS.
                if ("http".equals(uri.getScheme())) {
                    Uri secure = uri.buildUpon().scheme("https").build();
                    if (allowed(secure)) view.loadUrl(secure.toString());
                } else if (view == page) {
                    publish("Atom Wallet can't open this kind of link");
                }
                return true;
            }

            @Override public WebResourceResponse shouldInterceptRequest(WebView view, WebResourceRequest req) {
                Uri uri = req.getUrl();
                String scheme = uri.getScheme();
                if ("data".equals(scheme) || "blob".equals(scheme) || "about".equals(scheme)) return null;
                if (!"https".equals(scheme) || ENGINE_HOST.equalsIgnoreCase(uri.getHost())
                    || (req.isForMainFrame() && !allowed(uri))) return missing();
                return null;
            }

            @Override public void onPageStarted(WebView view, String url, Bitmap favicon) {
                if (view != page) return;
                current = url; title = ""; loading = true; progress = 0;
                publish(null);
            }

            @Override public void doUpdateVisitedHistory(WebView view, String url, boolean isReload) {
                if (view != page) return;
                current = url;
                publish(null);
            }

            @Override public void onPageFinished(WebView view, String url) {
                if (view != page) return;
                current = url; loading = false; progress = 100;
                if (view.getTitle() != null) title = view.getTitle();
                publish(null);
            }

            @Override public void onReceivedSslError(WebView view, SslErrorHandler handler, SslError error) {
                handler.cancel();
                if (view != page) return;
                loading = false;
                publish("This site's security certificate is not trusted");
            }

            @Override public boolean onRenderProcessGone(WebView view, RenderProcessGoneDetail detail) {
                if (view == page) {
                    close();
                    notify.accept("{\"type\":\"browser\",\"error\":\"The browser stopped. Open the page again from Explore.\"}");
                }
                return true;
            }
        });
        page.setWebChromeClient(new WebChromeClient() {
            @Override public void onProgressChanged(WebView view, int value) {
                if (view != page) return;
                progress = value;
                publish(null);
            }
            @Override public void onReceivedTitle(WebView view, String value) {
                if (view != page) return;
                title = value == null ? "" : value;
                publish(null);
            }
        });
        page.setDownloadListener((url, agent, disposition, mime, length) -> publish("Downloads are off in Atom Wallet"));
        host.addView(page);
    }

    void show(String url, View surface, int x, int y, int width, int height) {
        if (page == null) create();
        int[] origin = new int[2], parent = new int[2];
        surface.getLocationOnScreen(origin);
        host.getLocationOnScreen(parent);
        FrameLayout.LayoutParams frame = new FrameLayout.LayoutParams(width, height, Gravity.TOP | Gravity.LEFT);
        frame.leftMargin = origin[0] - parent[0] + x;
        frame.topMargin = origin[1] - parent[1] + y;
        page.setLayoutParams(frame);
        if (page.getVisibility() != View.VISIBLE) {
            page.setVisibility(View.VISIBLE);
            page.onResume();
        }
        if (!url.isEmpty()) {
            if (allowed(Uri.parse(url))) page.loadUrl(url);
            else publish("Atom Wallet only opens https:// addresses");
        } else {
            publish(null);
        }
    }

    boolean canGoBack() { return canGoBack; }
    void back() { if (page != null && page.canGoBack()) page.goBack(); }
    void forward() { if (page != null && page.canGoForward()) page.goForward(); }
    void reload() { if (page != null) page.reload(); }
    /** Hidden pages stop their timers and media until the browser is shown again. */
    void hide() {
        if (page == null || page.getVisibility() == View.GONE) return;
        page.setVisibility(View.GONE);
        page.onPause();
    }
    void close() {
        if (page != null) {
            WebView old = page;
            page = null;
            ((ViewGroup) old.getParent()).removeView(old);
            old.destroy();
        }
        current = ""; title = ""; loading = false; progress = 0;
        canGoBack = false;
    }
}
