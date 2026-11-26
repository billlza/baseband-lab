"""Fetch the two pinned public RF-Stream-PHY runs; verify every original I/Q file."""
import argparse
import concurrent.futures
import hashlib
import json
from pathlib import Path
import re
import urllib.request

DATASET = "lkk688/ofdm-preamble-intelligence"
REV = "e824d4b827529cf6b59f8658887a09958069bfc7"
SOURCE = f"https://huggingface.co/datasets/{DATASET}/resolve/{REV}"
TREE = f"https://huggingface.co/api/datasets/{DATASET}/tree/{REV}"
RUNS = {"qpsk": "coax/ber_sweep_v2/run_20260429_093858",
        "qam16": "coax/ber_sweep_v3/run_20260429_150637"}


def read(url):
    with urllib.request.urlopen(url, timeout=70) as response:
        return response.read()


def fetch(target):
    target.mkdir(parents=True, exist_ok=True)
    records = []
    jobs = []
    for mod, path in RUNS.items():
        folder = target/mod
        folder.mkdir(exist_ok=True)
        index = json.loads(read(f"{TREE}/{path}?limit=48"))
        files = sorted((obj for obj in index if re.fullmatch(r"cap_\d+_[a-z]+\.npz", Path(obj['path']).name)),
                       key=lambda obj: int(Path(obj['path']).name.split('_')[1]))[:8]
        if len(files)!=8 or len({obj['path'].split('_')[-2] for obj in files})!=8:
            raise ValueError(f"Incomplete or duplicate source inventory for {mod}")
        for item in ("rx_config.json", "run_summary.json"):
            (folder/item).write_bytes(read(f"{SOURCE}/{path}/{item}"))
        for obj in files:
            sha = obj['lfs']['oid']
            jobs.append((folder/Path(obj['path']).name, SOURCE+"/"+obj['path'], sha, obj['size']))
            records.append(dict(modulation=mod, path=obj['path'], bytes=obj['size'], sha256=sha))
    def ensure(job):
        p, url, sha, size = job
        blob = p.read_bytes() if p.is_file() else read(url)
        if len(blob)!=size or hashlib.sha256(blob).hexdigest()!=sha:
            raise ValueError(f"Invalid contents for {p.name}")
        if not p.is_file():
            p.write_bytes(blob)
    with concurrent.futures.ThreadPoolExecutor(max_workers=3) as pool:
        list(pool.map(ensure,jobs))
    (target/"manifest.json").write_text(json.dumps(dict(dataset=DATASET,revision=REV,runs=RUNS,files=records),indent=2)+"\n")
    print(f"{len(records)} original captures, {sum(x['bytes'] for x in records):,} bytes, all SHA-256 verified")

if __name__=="__main__":
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument("directory",type=Path)
    fetch(parser.parse_args().directory)
