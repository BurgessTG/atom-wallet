"""Build the native prover for the same ABIs as the Godot application."""
import os
from pathlib import Path
import platform
import shutil
import subprocess
import sys

root = Path(__file__).resolve().parent
ndk = Path(sys.argv[1])
out = Path(sys.argv[2])
subprocess.run([sys.executable, root / "prepare.py"], check=True)
host = {"Linux": "linux-x86_64", "Darwin": "darwin-x86_64"}[platform.system()]
bindir = ndk / "toolchains/llvm/prebuilt" / host / "bin"
for triple, abi in [("aarch64-linux-android", "arm64-v8a"), ("x86_64-linux-android", "x86_64")]:
    cc = str(bindir / f"{triple}28-clang")
    cxx = cc + "++"
    key = triple.replace("-", "_")
    env = dict(os.environ)
    env.update({
        f"CC_{key}": cc, f"CXX_{key}": cxx, f"AR_{key}": str(bindir / "llvm-ar"),
        f"CARGO_TARGET_{key.upper()}_LINKER": cc,
        f"CMAKE_TOOLCHAIN_FILE_{key}": str(ndk / "build/cmake/android.toolchain.cmake"),
        "ANDROID_NDK_HOME": str(ndk), "ANDROID_NDK_ROOT": str(ndk),
        "CMAKE_ANDROID_ARCH_ABI": abi, "ANDROID_ABI": abi, "ANDROID_PLATFORM": "android-28"
    })
    subprocess.run(["cargo", "build", "--locked", "--release", "--lib", "--target-dir", str(root / "target"), "--target", triple],
                   cwd=root, env=env, check=True)
    (out / abi).mkdir(parents=True, exist_ok=True)
    shutil.copyfile(root / "target" / triple / "release/libmdwa_prover.so", out / abi / "libmdwa_prover.so")
