#!/usr/bin/env python3
"""Fetch the pinned emote assets using only the Python standard library."""

import argparse
from concurrent.futures import ThreadPoolExecutor, as_completed
import hashlib
import json
from pathlib import Path
import sys
import tempfile
import time
from urllib.request import Request, urlopen

ROOT = Path(__file__).resolve().parents[1]
RESOURCES = ROOT / "Resources"
PNG_SIGNATURE = b"\x89PNG\r\n\x1a\n"


def matches(path, expected):
    if not path.is_file():
        return False
    data = path.read_bytes()
    return data.startswith(PNG_SIGNATURE) and hashlib.sha256(data).hexdigest() == expected


def download(item, destination, verify_only):
    expected = item["sha256"]
    if matches(destination, expected):
        return "cached"
    if verify_only:
        raise ValueError("missing image or SHA-256 mismatch")
    for attempt in range(3):
        try:
            request = Request(item["url"], headers={"User-Agent": "EmoteWheel-asset-downloader/1.0"})
            with urlopen(request, timeout=30) as response:
                data = response.read()
            if not data.startswith(PNG_SIGNATURE):
                raise ValueError("response is not a PNG")
            if hashlib.sha256(data).hexdigest() != expected:
                raise ValueError("SHA-256 mismatch; upstream asset may have changed")
            destination.parent.mkdir(parents=True, exist_ok=True)
            temporary = None
            try:
                with tempfile.NamedTemporaryFile(dir=destination.parent, suffix=".tmp", delete=False) as file:
                    temporary = Path(file.name)
                    file.write(data)
                temporary.replace(destination)
            finally:
                if temporary is not None:
                    temporary.unlink(missing_ok=True)
            return "downloaded"
        except Exception:
            if attempt == 2:
                raise
            time.sleep(attempt + 1)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--workers", type=int, default=8, choices=range(1, 17), metavar="1..16")
    parser.add_argument("--verify-only", action="store_true", help="check local assets without using the network")
    args = parser.parse_args()
    catalog = json.loads((RESOURCES / "emotes.json").read_text(encoding="utf-8"))
    sources = json.loads((RESOURCES / "emotes-sources.json").read_text(encoding="utf-8"))
    destinations = {str(item["id"]): RESOURCES / item["filename"] for item in catalog}
    if len(destinations) != len(catalog) or {str(item["id"]) for item in sources} != set(destinations):
        parser.error("catalog and source manifest IDs must match, without duplicates")
    if len(sources) != len(destinations):
        parser.error("duplicate IDs in source manifest")
    for path in destinations.values():
        if not path.resolve().is_relative_to((RESOURCES / "emotes").resolve()):
            parser.error("asset paths must stay inside Resources/emotes")
    counts = {"cached": 0, "downloaded": 0, "failed": 0}
    with ThreadPoolExecutor(max_workers=args.workers) as pool:
        jobs = {pool.submit(download, item, destinations[str(item["id"])], args.verify_only): item for item in sources}
        for completed, future in enumerate(as_completed(jobs), start=1):
            item = jobs[future]
            try:
                counts[future.result()] += 1
            except Exception as error:
                counts["failed"] += 1
                print(f"FAIL {item['id']}: {error}", file=sys.stderr, flush=True)
            if completed % 100 == 0 or completed == len(jobs):
                print(f"{completed}/{len(jobs)} checked; {counts['downloaded']} downloaded; {counts['failed']} failed", flush=True)
    print(f"Finished: {counts['cached']} already valid, {counts['downloaded']} downloaded, {counts['failed']} failed.")
    return 1 if counts["failed"] else 0


if __name__ == "__main__":
    sys.exit(main())
