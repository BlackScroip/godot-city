#!/usr/bin/env python3
"""Resume a public model download with validated HTTP byte ranges."""

from __future__ import annotations

import argparse
from concurrent.futures import ThreadPoolExecutor, as_completed
import hashlib
from pathlib import Path
import re
import shutil
import subprocess
import time


def download(url, output, size, workers, chunk_size, expected_sha256=None):
    output.parent.mkdir(parents=True, exist_ok=True)
    parts = output.with_name(output.name + ".parts")
    parts.mkdir(exist_ok=True)
    jobs = [(index, start, min(size - 1, start + chunk_size - 1))
            for index, start in enumerate(range(0, size, chunk_size))]

    def fetch(job):
        index, start, end = job
        target = parts / f"{index:06d}.part"
        length = end - start + 1
        if target.exists() and target.stat().st_size == length:
            return length
        for attempt in range(4):
            header = target.with_suffix(".headers")
            temporary = target.with_suffix(".download")
            result = subprocess.run([
                "curl", "--fail", "--location", "--silent", "--show-error",
                "--max-time", "90", "--max-filesize", str(length),
                "--range", f"{start}-{end}", "--dump-header", str(header),
                "--output", str(temporary), url,
            ], capture_output=True, text=True)
            headers = header.read_text(errors="replace") if header.exists() else ""
            ranges = re.findall(r"content-range:\s*bytes\s+(\d+)-(\d+)/(\d+)", headers, re.I)
            valid_range = ranges and tuple(map(int, ranges[-1])) == (start, end, size)
            if result.returncode == 0 and valid_range and temporary.stat().st_size == length:
                temporary.replace(target)
                return length
            if attempt == 3:
                raise RuntimeError(f"range {start}-{end} failed: {result.stderr.strip()}")
            time.sleep(attempt + 1)
        raise AssertionError("unreachable")

    started, completed, last_report = time.monotonic(), 0, 0.0
    with ThreadPoolExecutor(max_workers=workers) as executor:
        futures = [executor.submit(fetch, job) for job in jobs]
        for future in as_completed(futures):
            completed += future.result()
            now = time.monotonic()
            if now - last_report >= 10 or completed == size:
                speed = completed / max(now - started, 0.01)
                print(f"{completed}/{size} bytes ({completed / size:.1%}), {speed / 1048576:.2f} MiB/s", flush=True)
                last_report = now

    temporary = output.with_name(output.name + ".assembling")
    digest = hashlib.sha256()
    with temporary.open("wb") as stream:
        for index, _, _ in jobs:
            content = (parts / f"{index:06d}.part").read_bytes()
            stream.write(content)
            digest.update(content)
    checksum = digest.hexdigest()
    if temporary.stat().st_size != size or (expected_sha256 and checksum != expected_sha256):
        raise RuntimeError("assembled model does not match its expected size or SHA-256")
    temporary.replace(output)
    shutil.rmtree(parts)
    print(f"complete: {output}, sha256={checksum}", flush=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("url")
    parser.add_argument("output", type=Path)
    parser.add_argument("--size", type=int, required=True)
    parser.add_argument("--workers", type=int, default=16)
    parser.add_argument("--chunk-size", type=int, default=2 * 1024 * 1024)
    parser.add_argument("--sha256")
    args = parser.parse_args()
    if args.size <= 0 or not 1 <= args.workers <= 32 or args.chunk_size <= 0:
        parser.error("size/chunk-size must be positive and workers must be 1-32")
    download(args.url, args.output, args.size, args.workers, args.chunk_size, args.sha256)


if __name__ == "__main__":
    main()
