"""Build the packaged parser with workstation-specific paths removed from compiler diagnostics."""
import os
from pathlib import Path
import shutil
import subprocess

source = Path(__file__).resolve().parent
crate = source / "parser"
cargo_registry = Path(os.environ.get("CARGO_HOME", Path.home() / ".cargo")) / "registry" / "src"
env = dict(os.environ)
env["CARGO_ENCODED_RUSTFLAGS"] = "\x1f".join((
    "--remap-path-prefix=" + str(source) + "=/source",
    "--remap-path-prefix=" + str(cargo_registry) + "=/registry",
))
subprocess.run(["cargo", "+1.98.1", "build", "--locked", "--release", "--target", "wasm32-unknown-unknown"], cwd=crate, env=env, check=True)
built = crate / "target/wasm32-unknown-unknown/release/m7_radio_reader.wasm"
target = source.parent / "Receiver" / "radio.wasm"
target.parent.mkdir(exist_ok=True)
shutil.copyfile(built, target)
