# Atom Wallet for Android

Atom Wallet is the Android client for Midnight Preview, Preprod and Mainnet; choose the chain in **Settings → Chain**. Preprod and Mainnet need a Blockfrost project ID. Godot draws the controls, text, QR codes and artwork through its mobile Vulkan renderer. The APK bundles the Midnight SDK worker and a native Rust prover. One private WebMessagePort connects the UI to the SDK in Android System WebView. A second carries proof requests to the native library. Android keeps up to 64 MiB of HTTP cache for the public proving files. The SDK verifies circuit keys and public parameters against its release hashes when loading them. Private proof inputs stay in the app when local proving is selected.

<img src="../docs/screenshots/android-overview.png" alt="Atom Wallet home screen with the NIGHT balance, DUST, assets and recent activity" width="290">

## Use the wallet

The header shows the atom, the chain chip (tap it to switch chains), the eye that hides balances and the gear that opens Settings. Folded phones get bottom tabs (Wallet, Activity, Explore) and bottom sheets. Unfolded screens of 600 dp or more get a side rail, two-column screens and centred dialogs.

**Create a new wallet** generates a 24-word recovery phrase. Tap to reveal it, write it down, confirm three of its words and set a password. **I already have a wallet** restores from a 12 to 24-word phrase and scans shielded funds from the start of the chain. Each chain has its own wallet and password. The worker seals the seed with the password and keeps it in the app's IndexedDB storage.

**Wallet** shows available NIGHT, shielded and unshielded assets, DUST generation and recent activity. **Send** takes one shielded or unshielded recipient per transfer: choose an asset, paste or scan an address, enter an amount and review the DUST fee. **Scan** reads a QR address or `midnight:` link with the Google Play services code scanner. **Receive** shows, copies and shares the private or public address with its QR code. Tap **DUST** to register NIGHT for generation or stop it. Tap a custom asset to give it a name, symbol and decimal places. Sends and DUST changes are confirmed by pressing and holding.

**Activity** groups transactions by day; open one for its amounts, block, hash, recorded step timings and a link to the block explorer. **Explore** is a browser: type an address or a search in the bar, or open a suggested link (the chain's block explorer and, on Preview and Preprod, the faucet). It has back, forward, reload, share and open-in-default-browser controls and opens any HTTPS site. The browser runs in its own WebView with no connection to the wallet: it cannot load the wallet engine's origin, plain HTTP is upgraded to HTTPS, and camera, location, file access and downloads are off. Sites cannot connect to the wallet or request transactions.

**Settings** holds:

- **Chain** (Preview, Preprod or Mainnet, with the Blockfrost project ID and custom endpoints) and **Proving** (on the phone or through a proof server).
- **Biometric unlock**: the password is sealed by an Android Keystore key that needs a strong biometric and is invalidated by new enrolments.
- **Auto-lock** (at once, 1 minute or 5 minutes after leaving the app), **Change password** and **Lock now**.
- **Hide balances**, **Haptic feedback**, **Rescan wallet** and **Remove wallet from this phone**.
- **Developer mode**, which adds transaction lookup by hash under Explore and per-proof GPU timings to transaction steps.

Leaving the app locks the wallet after the auto-lock delay. A transaction that is proving or submitting keeps the worker running in the background for up to three minutes so it can finish; the wallet locks as soon as it does. If Android stops the app during a submission, check Activity after unlocking before sending again.

A forgotten password cannot be recovered. **Forgot password?** on the unlock screen erases that chain's wallet from the phone so it can be restored from its recovery phrase with a new password.

## Local proving

The native prover runs BLS12-381 scalar transforms and quotient division on Vulkan. A workgroup processes seven transform stages per dispatch and reuses public twiddle tables across calls. For large G1 multi-scalar multiplications (MSMs), the prover combines repeated coefficients, then splits each scalar into a low byte and 247 upper bits. Vulkan sums the low-byte buckets while the CPU computes the upper contribution on the same bases. The CPU combines both results, builds the witness, evaluates constraints and verifies the proof. The Android backend requires a hardware Vulkan compute adapter. Downloading uncached public circuit material requires internet. The Apple implementation that informed this work is [Seungheon Oh’s Metal prover](https://github.com/SeungheonOh/midnight-zk/tree/3531dff44cc66c5c6afaa15d49bae3b207362b04/metal).

## Build and install

Use JDK 17, Android SDK Platform 35 and Build Tools 35, Node.js 24 or newer, Godot 4.7.2 with Android export support, Python 3.12+, Rust 1.98 and NDK 28.2.13676358 on Linux or macOS. Set `JAVA_HOME` and `ANDROID_HOME` for your installation. From the repository root run

```sh
npm ci
rustup target add aarch64-linux-android x86_64-linux-android
./android/gradlew -p android :app:assembleDebug
adb install -r android/app/build/outputs/apk/debug/app-arm64-v8a-debug.apk
```

The build generates separate arm64 phone and x86_64 emulator APKs. The app requires Android 9 or newer, Vulkan 1.1 or newer, and a current Android System WebView. The debug build uses the development machine’s Android debug signing key. Android only installs an update over an existing app when both are signed with the same key.

## Check the mobile client

From the repository root, after building, run

```sh
godot --headless --path android/ui --script ../check-ui.gd
node android/check-progress.mjs
node android/check-worker.mjs
node android/check-worker.mjs --live
```

The UI check drives every screen through a stand-in for the Android bridge and checks controls, navigation and decimal precision; set `MDWA_TEST_VIEWPORT=744x820` to check the unfolded layout. The worker check uses a disposable Chromium profile to exercise the bundled worker, IndexedDB vault, QR encoding, session locking, password change and erase. Set `CHROMIUM` to your Chromium executable if it is outside `/usr/bin`. The live check creates a fresh throwaway Preview wallet and waits for balances and history. Neither check needs funded coins.

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

These measurements were taken on earlier builds, which had a **Test local prover** button and a bundled test dApp. The proof check they used remains available to `check-worker.mjs --proof`.

On a Samsung SM-F976U (Adreno 840), three native provers processed the same serialized shielded-output request. Each ran once in a fresh process and five more times in that process, with the order rotating each round. Timings include proving and internal verification. They exclude material downloads, USB transfer and independent verification by the stock ledger-v9 verifier. All 18 proofs passed. Android reported thermal status 0 before and after the comparison.

| Native backend | First proof | Warm median | Warm range |
| --- | ---: | ---: | ---: |
| [Previous Vulkan build](https://github.com/BurgessTG/mdwa/commit/8b6d2ce20b520a97f60eb480be38db2761387865) | 8.29 s | 6.38 s | 6.08–6.58 s |
| Optimized Vulkan + CPU | 3.66 s | 2.07 s | 1.74–2.36 s |
| Stock CPU | 2.72 s | 2.06 s | 1.66–2.32 s |

The optimized native path took 68% less time at the warm median. The CPU and optimized Vulkan ranges overlapped. A separate tuning run using coefficient compaction on both sides gave a warm median of 1.78 s on CPU alone and 1.96 s with Vulkan. The wallet keeps Vulkan active for transforms, quotient division and curve bucket sums.

The wallet test invoked **Test local prover** in an isolated Android app with the shipping wallet assets and native libraries. The first verified sample downloaded four public files and took 8.00 s. Five immediate repeats had a median of 2.82 s (2.23–2.85 s). After stopping and reopening the app, the first proof took 3.25 s. Android served all four public files from disk with zero network requests for those files. The previous build took 13.01 s and then 6.69 s in that test. These end-to-end timings include WebView work, material lookup and ledger verification.

Fresh processes on the Adreno 840 and RTX 2070 SUPER each generated a 4,853-byte shielded-output proof with 151 Vulkan transforms, 28 GPU-assisted MSMs and one quotient division. The stock v8 and v9 ledgers each accepted the corresponding proof and rejected a one-bit alteration. The packaged wallet worker also passed its proof-port test in desktop Chromium.

The UI pack passed the touch-flow checks. The earlier UI build synced a new Preview wallet in desktop Chromium. An Android 15 x86_64 emulator installed that build and selected Vulkan 1.3 with SwiftShader. Its stock WebView 124 renderer crashed at the same native instruction in MDWA and in the system WebView shell displaying a blank page. On a Samsung SM-F976U, a funded unshielded 1 tNIGHT self-transfer finalized on Midnight Preview. The handset also verified a synthetic shielded-output proof. A native contract deployment and a one-unit shielded mint subsequently finalized on Preview. The funded Samsung wallet recognized the output and balanced a shielded self-transfer for review. The send was cancelled at review for the owner to perform manually.
