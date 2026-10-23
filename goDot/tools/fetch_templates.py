#!/usr/bin/env python3
"""Fetch selected files from the pinned official template ZIP using HTTP ranges."""
import argparse
from concurrent.futures import ThreadPoolExecutor
import hashlib
import io
import json
import os
from pathlib import Path
import ssl
import time
import urllib.error
import urllib.request
import zipfile

VERSION = "4.7.2"
URL = f"https://github.com/godotengine/godot/releases/download/{VERSION}-stable/Godot_v{VERSION}-stable_export_templates.tpz"
BLOCK = 4 * 1024 * 1024


def open_release(request, timeout=180):
    certificate = os.environ.get("SSL_CERT_FILE")
    if not certificate and Path("/etc/ssl/cert.pem").exists():
        certificate = "/etc/ssl/cert.pem"
    context = ssl.create_default_context(cafile=certificate)
    for attempt in range(6):
        try:
            return urllib.request.urlopen(request, timeout=timeout, context=context)
        except (OSError, urllib.error.URLError):
            if attempt == 5:
                raise
            print(f"retry release request ({attempt + 1}/5)", flush=True)
            time.sleep(min(2 ** attempt, 15))


class RemoteZip(io.RawIOBase):
    def __init__(self, cache):
        self.cache = cache
        cache.mkdir(parents=True, exist_ok=True)
        with open_release(urllib.request.Request(URL, method="HEAD"), timeout=45) as response:
            self.url = response.url
            self.length = int(response.headers["Content-Length"])
        self.position = 0

    def seekable(self):
        return True

    def readable(self):
        return True

    def cache_member(self, info, jobs=1):
        start = info.header_offset // BLOCK * BLOCK
        end = min(self.length, ((info.header_offset + info.compress_size + 65536) // BLOCK + 1) * BLOCK)
        if jobs > 1:
            def fetch_block(offset):
                stop = min(offset + BLOCK, self.length)
                path = self.cache / f"{offset}-{stop}.bin"
                if path.exists() and path.stat().st_size == stop - offset:
                    return
                request = urllib.request.Request(self.url, headers={"Range": f"bytes={offset}-{stop - 1}"})
                with open_release(request) as response:
                    if response.status != 206 or not response.headers.get("Content-Range", "").startswith(f"bytes {offset}-"):
                        raise RuntimeError("Release server did not honor the requested byte range")
                    data = response.read(stop - offset + 1)
                if len(data) != stop - offset:
                    raise OSError("Truncated template block")
                temporary = path.with_suffix(".part")
                temporary.write_bytes(data)
                temporary.replace(path)
                print(f"cached {offset}:{stop}", flush=True)
            with ThreadPoolExecutor(max_workers=jobs) as executor:
                list(executor.map(fetch_block, range(start, end, BLOCK)))
            return
        request = urllib.request.Request(self.url, headers={"Range": f"bytes={start}-{end - 1}"})
        with open_release(request) as response:
            if response.status != 206 or not response.headers.get("Content-Range", "").startswith(f"bytes {start}-"):
                raise RuntimeError("Release server did not honor the requested byte range")
            while start < end:
                stop = min(start + BLOCK, end)
                data = response.read(stop - start)
                if len(data) != stop - start:
                    raise OSError("Truncated template block")
                path = self.cache / f"{start}-{stop}.bin"
                temporary = path.with_suffix(".part")
                temporary.write_bytes(data)
                temporary.replace(path)
                print(f"cached {start}:{stop}", flush=True)
                start = stop

    def tell(self):
        return self.position

    def seek(self, offset, whence=0):
        self.position = offset + (0 if whence == 0 else self.position if whence == 1 else self.length)
        return self.position

    def read(self, count=-1):
        end = self.length if count < 0 else min(self.length, self.position + count)
        parts = []
        while self.position < end:
            start = self.position // BLOCK * BLOCK
            stop = min(start + BLOCK, self.length)
            path = self.cache / f"{start}-{stop}.bin"
            if not path.exists() or path.stat().st_size != stop - start:
                request = urllib.request.Request(self.url, headers={"Range": f"bytes={start}-{stop - 1}"})
                for attempt in range(6):
                    try:
                        with open_release(request) as response:
                            if response.status != 206 or not response.headers.get("Content-Range", "").startswith(f"bytes {start}-"):
                                raise RuntimeError("Release server did not honor the requested byte range")
                            data = response.read(stop - start + 1)
                        if len(data) != stop - start:
                            raise OSError("Truncated template block")
                        break
                    except (OSError, urllib.error.URLError):
                        if attempt == 5:
                            raise
                        print(f"retry block {start} ({attempt + 1}/5)", flush=True)
                        time.sleep(min(2 ** attempt, 15))
                temporary = path.with_suffix(".part")
                temporary.write_bytes(data)
                temporary.replace(path)
                print(f"cached {start}:{stop}", flush=True)
            data = path.read_bytes()
            amount = min(end - self.position, stop - self.position)
            parts.append(data[self.position - start:self.position - start + amount])
            self.position += amount
        return b"".join(parts)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, default=Path(__file__).resolve().parents[1] / ".local/templates")
    parser.add_argument("--files", nargs="+", default=["macos.zip", "android_debug.apk"])
    parser.add_argument("--bulk", action="store_true", help="Fetch each compressed member in one ranged request")
    parser.add_argument("--jobs", type=int, choices=range(1, 9), default=1, help="Concurrent ranged requests when using --bulk")
    options = parser.parse_args()
    options.output.mkdir(parents=True, exist_ok=True)
    remote = RemoteZip(options.output / ".blocks")
    archive = zipfile.ZipFile(remote)
    manifest_path = options.output / "manifest.json"
    manifest = json.loads(manifest_path.read_text()) if manifest_path.exists() else {"version": VERSION, "source": URL, "files": {}}
    for name in options.files:
        info = archive.getinfo("templates/" + name)
        target = options.output / name
        if target.exists() and target.stat().st_size == info.file_size and manifest["files"].get(name, {}).get("sha256") == hashlib.sha256(target.read_bytes()).hexdigest():
            print(f"verified {name}", flush=True)
            continue
        temporary = target.with_suffix(target.suffix + ".part")
        if options.bulk:
            remote.cache_member(info, options.jobs)
        digest = hashlib.sha256()
        with archive.open(info) as source, temporary.open("wb") as destination:
            while chunk := source.read(1024 * 1024):
                destination.write(chunk)
                digest.update(chunk)
        temporary.replace(target)
        manifest["files"][name] = {"bytes": info.file_size, "zip_crc32": f"{info.CRC:08x}", "sha256": digest.hexdigest()}
        manifest_path.write_text(json.dumps(manifest, indent=2) + "\n")
        print(f"ready {name}: {info.file_size} bytes", flush=True)


if __name__ == "__main__":
    main()
