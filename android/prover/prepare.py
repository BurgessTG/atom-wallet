"""Prepare checksum-pinned upstream crates for Cargo's local Vulkan patches."""
from pathlib import Path
import hashlib
import io
import os
import shutil
import tarfile
import tempfile
import urllib.request

root = Path(__file__).resolve().parent
output = root / ".upstream"
output.mkdir(exist_ok=True)
versions = {
    ("midnight-curves", "0.2.1"): "71a947535f03578bdc6401354accbf515257dcbaca7fb6a73c48fb0c17281a6c",
    ("midnight-curves", "0.3.1"): "efaa236cfabccb367c0a89e58a6e8f0b4ba70fb81efd07acfe1d3a0ec3bed081",
    ("midnight-proofs", "0.7.3"): "86d40952370a114d52a1ca5a5730a1a96e07380bb1a632ef7f494bd38c7bd482",
    ("midnight-proofs", "0.8.2"): "22b1526bc7d9d1fad29505a15b81fe54aa7698a7dcd1948b447021bc8571f543",
}
def insert(path, marker, hook):
    body = path.read_text()
    if body.count(marker) != 1:
        raise ValueError(f"Missing patch location in {path}")
    path.write_text(body.replace(marker, marker + "\n" + (root / hook).read_text()))

patch_revision = hashlib.sha256(Path(__file__).read_bytes())
for hook in sorted(root.glob("*-hook.rs.inc")):
    patch_revision.update(hook.read_bytes())

for (crate, version), digest in versions.items():
    name = f"{crate}-{version}"
    dest = output / name
    stamp = dest / ".mdwa-patch-revision"
    revision = patch_revision.hexdigest() + digest
    if stamp.exists() and stamp.read_text() == revision:
        continue
    # Keep the release archive so changing the hook works offline.
    archive = output / f"{name}.crate"
    if not archive.exists():
        cache = Path(os.environ.get("CARGO_HOME", Path.home() / ".cargo")) / "registry/cache"
        local = next(cache.glob(f"*/{name}.crate"), None)
        data = local.read_bytes() if local else urllib.request.urlopen(
            f"https://static.crates.io/crates/{crate}/{name}.crate", timeout=60).read()
    else:
        data = archive.read_bytes()
    if hashlib.sha256(data).hexdigest() != digest:
        raise ValueError(f"Invalid {name} source checksum")
    archive.write_bytes(data)
    with tempfile.TemporaryDirectory(dir=output) as tmp:
        with tarfile.open(fileobj=io.BytesIO(data)) as package:
            package.extractall(tmp, filter="data")
        src = Path(tmp) / name
        if crate == "midnight-curves":
            insert(src / "src/fft.rs", "pub fn best_fft<Scalar: Field, G: FftGroup<Scalar>>(a: &mut [G], omega: Scalar, log_n: u32) {", "fft-hook.rs.inc")
            insert(src / "src/bls12_381/g1.rs", "pub fn multi_exp(points: &[Self], scalars: &[Fq]) -> Self {", "msm-hook.rs.inc")
        else:
            insert(src / "src/poly/domain.rs", "// Divide to obtain the quotient polynomial in the coset evaluation\n        // domain.", "quotient-hook.rs.inc")
        with (src / "Cargo.toml").open("a") as manifest:
            manifest.write('\n[dependencies.mdwa-vulkan]\npath = "../../gpu"\n')
        shutil.copytree(src, dest, dirs_exist_ok=True)
        stamp.write_text(revision)
