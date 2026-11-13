#!/usr/bin/env python3
"""Report the newest stable arm64 CEF standard artifact without changing the pin."""
import argparse
import json
from pathlib import Path
import re
import sys
import time
import urllib.parse
import urllib.request

INDEX_URL = "https://cef-builds.spotifycdn.com/index.json"
MAX_BYTES = 32 * 1024 * 1024


class HTTPSRedirects(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, request, response, code, message, headers, url):
        if urllib.parse.urlsplit(url).scheme != "https":
            raise ValueError("Metadata redirect must remain HTTPS")
        return super().redirect_request(request, response, code, message, headers, url)


def version_key(cef, chromium):
    match = re.fullmatch(r"(\d+)\.(\d+)\.(\d+)\+g([0-9a-f]+)\+chromium-(\d+\.\d+\.\d+\.\d+)", cef)
    if not match or match[5] != chromium:
        raise ValueError(f"Unexpected CEF/Chromium version pair: {cef}, {chromium}")
    return tuple(map(int, chromium.split("."))), tuple(map(int, match.group(1, 2, 3)))


def read_index():
    opener = urllib.request.build_opener(HTTPSRedirects())
    deadline = time.monotonic() + 60
    with opener.open(INDEX_URL, timeout=20) as response:
        if int(response.headers.get("Content-Length", "0")) > MAX_BYTES:
            raise ValueError("Metadata exceeds 32 MiB response limit")
        data = bytearray()
        while len(data) <= MAX_BYTES:
            if time.monotonic() > deadline:
                raise TimeoutError("Metadata read exceeded 60 seconds")
            chunk = response.read(min(65536, MAX_BYTES + 1 - len(data)))
            if not chunk:
                return json.loads(data)
            data.extend(chunk)
        raise ValueError("Metadata exceeds 32 MiB response limit")


def artifact(version):
    candidates = [f for f in version["files"] if f["type"] == "standard"]
    if len(candidates) != 1:
        raise ValueError("Expected exactly one standard artifact for selected version")
    entry = candidates[0]
    name = entry["name"]
    expected = f'cef_binary_{version["cef_version"]}_macosarm64.tar.bz2'
    if name != expected or not re.fullmatch(r"[0-9a-f]{40}", entry["sha1"]):
        raise ValueError("Invalid artifact name or published SHA1")
    if type(entry["size"]) is not int or entry["size"] <= 0:
        raise ValueError("Invalid artifact size")
    return {"url": "https://cef-builds.spotifycdn.com/" + urllib.parse.quote(name, safe=""),
            "sizeBytes": entry["size"], "publishedAt": entry["last_modified"],
            "checksums": {"sha1": entry["sha1"]}}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--lock", type=Path, default=Path(__file__).resolve().parents[2] / "Vendor/CEF.lock")
    args = parser.parse_args()
    result = {"status": "error", "metadataUrl": INDEX_URL, "updateAvailable": None}
    try:
        lock = json.loads(args.lock.read_text())
        if (lock["platform"], lock["channel"], lock["distribution"]) != ("macosarm64", "stable", "standard"):
            raise ValueError("Lock must select stable macosarm64 standard CEF")
        current_key = version_key(lock["cef_version"], lock["chromium_version"])
        result["current"] = {"cefVersion": lock["cef_version"], "cefCommit": lock["cef_commit"],
                             "chromiumVersion": lock["chromium_version"],
                             "artifact": {"url": lock["url"], "sizeBytes": lock["size_bytes"],
                                          "checksums": {"sha1": lock["published_sha1"], "sha256": lock["sha256"]}}}
        versions = [v for v in read_index()["macosarm64"]["versions"] if v["channel"] == "stable"]
        if not versions:
            raise ValueError("Metadata contains no stable macosarm64 versions")
        latest = max(versions, key=lambda v: version_key(v["cef_version"], v["chromium_version"]))
        result["latest"] = {"cefVersion": latest["cef_version"], "chromiumVersion": latest["chromium_version"],
                            "cefCommitPrefix": latest["cef_version"].split("+g")[1].split("+")[0],
                            "artifact": artifact(latest)}
        result["updateAvailable"] = version_key(latest["cef_version"], latest["chromium_version"]) > current_key
        result["status"] = "ok"
    except Exception as error:
        result["error"] = str(error)
    print(json.dumps(result, indent=2))
    return 0 if result["status"] == "ok" else 1


if __name__ == "__main__":
    sys.exit(main())
