# MDWA for Android

This Android client uses Midnight Preview. Godot draws the controls, text, QR codes and artwork through its mobile Vulkan renderer. The APK bundles the Midnight SDK worker and a native Rust prover. One private WebMessagePort connects the UI to the SDK in Android System WebView. A second carries proof requests to the native library. The SDK verifies the downloaded circuit keys and public parameters against its release hashes. Private proof inputs stay in the app when local proving is selected.

<img src="../docs/screenshots/android-overview.png" alt="Android demo wallet showing available NIGHT, DUST capacity and wallet navigation" width="290">

## Use the wallet

Choose **Create wallet** to generate a recovery phrase, record it in order and set a password. **Restore wallet** opens an existing Preview wallet from its phrase and starts its shielded scan at the beginning of the chain. The worker encrypts the vault in the app’s IndexedDB storage. Leaving the app closes the worker and locks the wallet. If you leave during submission, check Activity after unlocking before retrying.

The client shows available NIGHT, shielded and unshielded assets, DUST generation and transaction history. **Receive** displays and copies the selected public, shielded or DUST generation address. **Send** prepares a single public NIGHT transfer for review. DUST registration and deregistration each have a separate fee review. The Chrome extension provides the other networks, multi-recipient sends, token management and dApp connections.

**Explore demo wallet** opens an offline sample with a transfer review and DUST registration walkthrough. Sample balances and confirmations exist only in that session.

## Local proving

In an unlocked wallet, open **Session → Test local prover**. The app generates a sample shielded output, proves it locally and checks it with the stock ledger-v9 verifier. Downloading uncached public circuit material requires internet. The displayed time includes that download and verification. The test uses no funds and sends no transaction.

The native prover runs BLS12-381 scalar transforms, G1 bucket summation for large multi-scalar multiplications, and quotient division on Vulkan compute. The CPU builds the witness, evaluates constraints, combines the MSM buckets, and verifies the result. The Android backend requires a hardware Vulkan compute adapter. The Apple implementation that informed this work is [Seungheon Oh’s Metal prover](https://github.com/SeungheonOh/midnight-zk/tree/3531dff44cc66c5c6afaa15d49bae3b207362b04/metal).

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

On an RTX 2070 SUPER, a shielded-output proof used 151 Vulkan transforms, 30 GPU-assisted MSMs and one quotient division. The stock v8 and v9 ledgers each accepted a proof and rejected a one-bit alteration. The packaged wallet worker also proved and verified a sample through its private message ports in desktop Chromium with a host native prover.

The UI pack passed the touch-flow checks. The earlier UI build synced a new Preview wallet in desktop Chromium. An Android 15 x86_64 emulator installed that build and selected Vulkan 1.3 with SwiftShader. Its stock WebView 124 renderer crashed at the same native instruction in MDWA and in the system WebView shell displaying a blank page. The live wallet session on a physical arm64 phone and submission of a funded transaction are still unverified.
