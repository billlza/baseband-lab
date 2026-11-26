# Receiver parser build

The browser module uses Mooring's MR7450 allowlist, radio sample representation and CSV writer. The small patch permits an empty network display name while disconnected. An attached radio still requires a valid name. Build from this directory with Git, Rust 1.98.1 and its WebAssembly standard library.

```sh
git clone https://github.com/billlza/mooring.git mooring
git -C mooring checkout --detach 40fdede1d1e57c80a8cc00074d97c617a73d87ef
git -C mooring apply ../no-service.patch
rustup target add --toolchain 1.98.1 wasm32-unknown-unknown
python3 build_parser.py
```

The resulting module is `parser/target/wasm32-unknown-unknown/release/m7_radio_reader.wasm`. The extension loads it locally as `Receiver/radio.wasm`. The core and the adapter use the GNU GPL, version 3 or later. The portable receiver validation replays synthetic status responses and compares source-PHY packets against numerical references derived from the author's CoaxSweep recordings. [Source dataset and CC BY 4.0 license](https://huggingface.co/datasets/lkk688/ofdm-preamble-intelligence/blob/e824d4b827529cf6b59f8658887a09958069bfc7/README.md)
