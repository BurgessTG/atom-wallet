package dev.burgesstg.mdwa;

import android.os.Handler;
import android.os.HandlerThread;
import android.os.Looper;
import android.util.Base64;
import android.webkit.WebMessage;
import android.webkit.WebMessagePort;
import java.util.Arrays;
import java.util.concurrent.atomic.AtomicBoolean;

/** A page-private proof port. Only complete, ordered frames enter JNI. */
final class NativeProver implements AutoCloseable {
    private static native byte[] prove(byte[] frame);
    private final HandlerThread thread = new HandlerThread("MDWA proof");
    private final WebMessagePort port;
    private final AtomicBoolean closed = new AtomicBoolean();
    private byte[] frame;
    private int offset;
    private boolean discard;
    private final Handler main = new Handler(Looper.getMainLooper());

    NativeProver(WebMessagePort port) {
        this.port = port;
        thread.start();
        port.setWebMessageCallback(new WebMessagePort.WebMessageCallback() {
            @Override public void onMessage(WebMessagePort source, WebMessage message) {
                if (!closed.get()) accept(message.getData());
            }
        }, new Handler(thread.getLooper()));
    }

    private void accept(String message) {
        boolean end = "end".equals(message);
        try {
            if (message.startsWith("begin ")) {
                int length = Integer.parseInt(message.substring(6));
                if (length < 1 || length > Runtime.getRuntime().maxMemory() / 2 || frame != null)
                    throw new IllegalArgumentException();
                frame = new byte[length];
                offset = 0;
            } else if (end) {
                if (discard || frame == null || offset != frame.length) throw new IllegalArgumentException();
                System.loadLibrary("mdwa_prover");
                byte[] proof = prove(frame);
                reply("{\"proof\":\"" + Base64.encodeToString(proof, Base64.NO_WRAP) + "\"}");
            } else if (!discard) {
                byte[] chunk = Base64.decode(message, Base64.NO_WRAP);
                System.arraycopy(chunk, 0, frame, offset, chunk.length);
                offset += chunk.length;
            }
        } catch (RuntimeException | LinkageError error) {
            discard = true;
            if (end) reply("{\"error\":\"Local Vulkan proof failed. Check available memory and Vulkan support.\"}");
        } finally {
            if ((end || discard) && frame != null) {
                Arrays.fill(frame, (byte) 0);
                frame = null;
            }
            if (end) discard = false;
        }
    }

    private void reply(String json) {
        main.post(() -> {
            if (!closed.get()) port.postMessage(new WebMessage(json));
        });
    }

    @Override public void close() {
        closed.set(true);
        port.close();
        thread.quit();
    }
}
