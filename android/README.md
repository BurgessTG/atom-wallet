# MDWA for Android

This Android client uses Midnight Preview. Godot draws the controls, text, QR codes and artwork through its mobile Vulkan renderer. The APK bundles the Midnight SDK worker and a native Rust prover. One private WebMessagePort connects the UI to the SDK in Android System WebView. A second carries proof requests to the native library. Android keeps up to 64 MiB of HTTP cache for the public proving files. The SDK verifies circuit keys and public parameters against its release hashes when loading them. Private proof inputs stay in the app when local proving is selected.

<img src="../docs/screenshots/android-overview.png" alt="Android demo wallet showing available NIGHT, DUST capacity and wallet navigation" width="290">

## Use the wallet

Choose **Create wallet** to generate a recovery phrase, record it in order and set a password. **Restore wallet** opens an existing Preview wallet from its phrase and starts its shielded scan at the beginning of the chain. The worker encrypts the vault in the app’s IndexedDB storage. Leaving the app closes the worker and locks the wallet. If you leave during submission, check Activity after unlocking before retrying.

The client shows available NIGHT, shielded and unshielded assets, DUST generation and transaction history. **Receive** displays and copies the selected public, shielded or DUST generation address. **Send** prepares a single public NIGHT transfer for review. DUST registration and deregistration each have a separate fee review. The Chrome extension provides the other networks, multi-recipient sends, token management and dApp connections.

**Explore demo wallet** opens an offline sample with a transfer review and DUST registration walkthrough. Sample balances and confirmations exist only in that session.

## Local proving

Choose **Test local prover** on the welcome screen or under **Session** in an unlocked wallet. The app generates a sample shielded output, proves it locally and checks it with the stock ledger-v9 verifier. Downloading uncached public circuit material requires internet. The displayed time includes that download and verification. The test uses no funds and sends no transaction.

The native prover runs BLS12-381 scalar transforms and quotient division on Vulkan. A workgroup processes seven transform stages per dispatch and reuses public twiddle tables across calls. For large G1 multi-scalar multiplications (MSMs), the prover combines repeated coefficients, then splits each scalar into a low byte and 247 upper bits. Vulkan sums the low-byte buckets while the CPU computes the upper contribution on the same bases. The CPU combines both results, builds the witness, evaluates constraints and verifies the proof. The Android backend requires a hardware Vulkan compute adapter. The Apple implementation that informed this work is [Seungheon Oh’s Metal prover](https://github.com/SeungheonOh/midnight-zk/tree/3531dff44cc66c5c6afaa15d49bae3b207362b04/metal).

## Build and install

Use JDK 17, Android SDK Platform 35 and Build Tools 35, Node.js 24 or newer, Godot 4.7.2 with Android export support, Python 3.12+, Rust 1.98 and NDK 28.2.13676358 on Linux or macOS. Set `JAVA_HOME` and `ANDROID_HOME` for your installation. From the repository root run

```sh
npm ci
rustup target add aarch64-linux-android x86_64-linux-android
./android/gradlew -p android :app:assembleDebug
adb install -r android/app/build/outputs/apk/debug/app-arm64-v8a-debug.apk
```

The build generates separate arm64 phone and x86_64 emulator APKs. The app requires Android 9 or newer, Vulkan 1.1 or newer, and a current Android System WebView. The debug build uses the development machine’s Android debug signing key.

## Check the mobile client

From the repository root, after building, run

```sh
godot --headless --path android/ui --script ../check-ui.gd
node android/check-worker.mjs
node android/check-worker.mjs --live
```

The UI check exercises controls, navigation, decimal precision and demo isolation. The worker check uses a disposable Chromium profile to exercise the bundled worker, IndexedDB vault, QR encoding and session locking. Set `CHROMIUM` to your Chromium executable if it is outside `/usr/bin`. The live check creates a fresh throwaway Preview wallet and waits for balances and history. Neither check needs funded coins. Open the desktop demo with `godot --path android/ui`.

To test the packaged worker and both proof ports with a hardware Vulkan GPU on the build host, run

```sh
python3 android/prover/prepare.py
cargo build --locked --release --manifest-path android/prover/Cargo.toml --bin proof-check
node android/check-worker.mjs --proof
node android/check-proof.mjs
node android/check-proof.mjs --v8
cargo test --locked --release --manifest-path android/prover/Cargo.toml --test vulkan
```

### Device verification

On a Samsung SM-F976U (Adreno 840), three native provers processed the same serialized shielded-output request. Each ran once in a fresh process and five more times in that process, with the order rotating each round. Timings include proving and internal verification. They exclude material downloads, USB transfer and independent verification by the stock ledger-v9 verifier. All 18 proofs passed. Android reported thermal status 0 before and after the comparison.

| Native backend | First proof | Warm median | Warm range |
| --- | ---: | ---: | ---: |
| [Previous Vulkan build](https://github.com/BurgessTG/mdwa/commit/8b6d2ce20b520a97f60eb480be38db2761387865) | 8.29 s | 6.38 s | 6.08–6.58 s |
| Optimized Vulkan + CPU | 3.66 s | 2.07 s | 1.74–2.36 s |
| Stock CPU | 2.72 s | 2.06 s | 1.66–2.32 s |

The optimized native path took 68% less time at the warm median. The CPU and optimized Vulkan ranges overlapped. A separate tuning run using coefficient compaction on both sides gave a warm median of 1.78 s on CPU alone and 1.96 s with Vulkan. The wallet keeps Vulkan active for transforms, quotient division and curve bucket sums.

The wallet test invoked **Test local prover** in an isolated Android app with the shipping wallet assets and native libraries. The first verified sample downloaded four public files and took 8.00 s. Five immediate repeats had a median of 2.82 s (2.23–2.85 s). After stopping and reopening the app, the first proof took 3.25 s. Android served all four public files from disk with zero network requests for those files. The previous build took 13.01 s and then 6.69 s in that test. These end-to-end timings include WebView work, material lookup and ledger verification.

Fresh processes on the Adreno 840 and RTX 2070 SUPER each generated a 4,853-byte shielded-output proof with 151 Vulkan transforms, 28 GPU-assisted MSMs and one quotient division. The stock v8 and v9 ledgers each accepted the corresponding proof and rejected a one-bit alteration. The packaged wallet worker also passed its proof-port test in desktop Chromium.

The UI pack passed the touch-flow checks. The earlier UI build synced a new Preview wallet in desktop Chromium. An Android 15 x86_64 emulator installed that build and selected Vulkan 1.3 with SwiftShader. Its stock WebView 124 renderer crashed at the same native instruction in MDWA and in the system WebView shell displaying a blank page. The handset test used a synthetic shielded output. Funded transaction submission remains unverified.
