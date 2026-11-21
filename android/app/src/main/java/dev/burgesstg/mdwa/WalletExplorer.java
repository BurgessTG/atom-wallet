package dev.burgesstg.mdwa;

import android.app.Activity;
import android.graphics.Color;
import android.net.Uri;
import android.view.Gravity;
import android.view.View;
import android.view.ViewGroup;
import android.webkit.RenderProcessGoneDetail;
import android.webkit.WebResourceRequest;
import android.webkit.WebResourceResponse;
import android.webkit.WebView;
import android.webkit.WebViewClient;
import android.widget.FrameLayout;
import java.io.ByteArrayInputStream;
import java.io.IOException;
import java.util.Collections;
import java.util.function.Consumer;
import org.json.JSONObject;

/** Two public destinations in a separate view with no wallet message port. */
final class WalletExplorer {
    private static final String LOCAL = "mdwa.local";
    private static final String EXPLORER = "explorer.preview.midnight.network";
    private final Activity activity;
    private final FrameLayout host;
    private final Consumer<String> notify;
    private WebView page;
    private volatile boolean canGoBack;

    WalletExplorer(Activity activity, Consumer<String> notify) {
        this.activity = activity;
        this.notify = notify;
        host = activity.findViewById(android.R.id.content);
    }

    private static boolean allowed(Uri uri) {
        return "https".equals(uri.getScheme()) && (uri.getPort() == -1 || uri.getPort() == 443)
            && uri.getUserInfo() == null && (LOCAL.equals(uri.getHost()) || EXPLORER.equals(uri.getHost()));
    }

    private static WebResourceResponse missing() {
        return new WebResourceResponse("text/plain", "UTF-8", 404, "Missing",
            Collections.emptyMap(), new ByteArrayInputStream(new byte[0]));
    }

    private void create() {
        page = new WebView(activity);
        page.setBackgroundColor(Color.rgb(12, 23, 27));
        page.getSettings().setAllowFileAccess(false);
        page.getSettings().setAllowContentAccess(false);
        page.getSettings().setJavaScriptEnabled(true);
        page.getSettings().setDomStorageEnabled(true);
        page.setVerticalScrollBarEnabled(false);
        page.setWebViewClient(new WebViewClient() {
            @Override public boolean shouldOverrideUrlLoading(WebView view, WebResourceRequest req) {
                Uri uri = req.getUrl();
                if (!req.isForMainFrame() || !allowed(uri)) return true;
                String path = uri.getPath();
                if (LOCAL.equals(uri.getHost()) && ("/open/token".equals(path) || "/open/counter".equals(path))) {
                    if (req.hasGesture() && "https://mdwa.local/".equals(view.getUrl())) {
                        notify.accept("{\"type\":\"exploreAction\",\"kind\":" + JSONObject.quote(uri.getLastPathSegment()) + "}");
                    }
                    return true;
                }
                return false;
            }

            @Override public WebResourceResponse shouldInterceptRequest(WebView view, WebResourceRequest req) {
                Uri uri = req.getUrl();
                if (!"https".equals(uri.getScheme()) || "appassets.androidplatform.net".equalsIgnoreCase(uri.getHost())
                    || (req.isForMainFrame() && !allowed(uri))) return missing();
                if (!LOCAL.equals(uri.getHost())) return null;
                if (!allowed(uri) || !"/".equals(uri.getPath()) || !"GET".equals(req.getMethod())) return missing();
                try {
                    return new WebResourceResponse("text/html", "UTF-8", activity.getAssets().open("explore/index.html"));
                } catch (IOException e) { return missing(); }
            }

            @Override public void onPageFinished(WebView view, String url) {
                if (view != page) return;
                canGoBack = view.canGoBack();
                notify.accept("{\"type\":\"browser\",\"url\":" + JSONObject.quote(url) + "}");
            }

            @Override public boolean onRenderProcessGone(WebView view, RenderProcessGoneDetail detail) {
                if (view == page) {
                    close();
                    notify.accept("{\"type\":\"browser\",\"error\":\"Browser stopped. Reopen it from Explore.\"}");
                }
                return true;
            }
        });
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
        page.setVisibility(View.VISIBLE);
        if (!url.isEmpty() && allowed(Uri.parse(url))) {
            canGoBack = false;
            page.loadUrl(url);
        }
    }

    boolean canGoBack() { return canGoBack; }
    void back() { if (page != null && page.canGoBack()) page.goBack(); }
    void reload() { if (page != null) page.reload(); }
    void hide() { if (page != null) page.setVisibility(View.GONE); }
    void close() {
        if (page != null) {
            WebView old = page;
            page = null;
            ((ViewGroup) old.getParent()).removeView(old);
            old.destroy();
        }
        canGoBack = false;
    }
}
