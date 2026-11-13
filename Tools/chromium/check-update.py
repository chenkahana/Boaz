#!/usr/bin/env python3
"""Check official Mac stable Chromium metadata without changing the source pin."""
import argparse
import datetime
import json
from pathlib import Path
import re
import sys
import time
import urllib.parse
import urllib.request

HOST = "chromiumdash.appspot.com"
URL = f"https://{HOST}/fetch_releases?platform=mac&channel=stable&num=1&offset=0"
MAX_BYTES = 1024 * 1024


def validate_url(url):
    parsed = urllib.parse.urlsplit(url)
    if (parsed.scheme != "https" or parsed.hostname != HOST or
            parsed.port not in (None, 443) or parsed.username or parsed.password):
        raise ValueError("Metadata must remain on the official HTTPS host")


class OfficialRedirects(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, request, response, code, message, headers, url):
        validate_url(url)
        return super().redirect_request(request, response, code, message, headers, url)


def version(value):
    if not isinstance(value, str) or not re.fullmatch(r"[0-9]{1,10}(?:\.[0-9]{1,10}){3}", value):
        raise ValueError("Invalid four-component Chromium version")
    return tuple(map(int, value.split(".")))


def metadata():
    deadline = time.monotonic() + 60
    opener = urllib.request.build_opener(OfficialRedirects())
    with opener.open(URL, timeout=20) as response:
        validate_url(response.url)
        if int(response.headers.get("Content-Length", "0")) > MAX_BYTES:
            raise ValueError("Release metadata exceeds 1 MiB")
        data = bytearray()
        while True:
            if time.monotonic() >= deadline:
                raise TimeoutError("Release metadata exceeded the 60-second read deadline")
            chunk = response.read1(min(65536, MAX_BYTES + 1 - len(data)))
            if time.monotonic() >= deadline:
                raise TimeoutError("Release metadata exceeded the 60-second read deadline")
            data.extend(chunk)
            if len(data) > MAX_BYTES:
                raise ValueError("Release metadata exceeds 1 MiB")
            if not chunk:
                return json.loads(data)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--lock", type=Path, default=Path(__file__).with_name("source.lock.json"))
    args = parser.parse_args()
    result = {"status": "error", "updateAvailable": None}
    try:
        current = json.loads(args.lock.read_text())["chromium_version"]
        current_key = version(current)
        result["currentVersion"] = current
        releases = metadata()
        if not isinstance(releases, list) or len(releases) != 1 or not isinstance(releases[0], dict):
            raise ValueError("Expected exactly one official stable release")
        release = releases[0]
        if str(release.get("platform", "")).lower() != "mac" or str(release.get("channel", "")).lower() != "stable":
            raise ValueError("Release metadata does not identify Mac stable")
        latest = release["version"]
        latest_key = version(latest)
        result["latestVersion"] = latest
        timestamp = release.get("time")
        if timestamp is not None:
            if type(timestamp) is not int or timestamp <= 0:
                raise ValueError("Invalid release timestamp")
            result["releaseDate"] = datetime.datetime.fromtimestamp(
                timestamp / 1000, datetime.timezone.utc).isoformat()
        hashes = release.get("hashes")
        if hashes is not None:
            if not isinstance(hashes, dict):
                raise ValueError("Invalid release hashes")
            chromium_hash = hashes.get("chromium")
            if chromium_hash is not None:
                if not isinstance(chromium_hash, str) or not re.fullmatch(r"[0-9a-fA-F]{40}", chromium_hash):
                    raise ValueError("Invalid Chromium revision hash")
                result["chromiumHash"] = chromium_hash.lower()
        result.update(status="ok", updateAvailable=latest_key > current_key)
    except Exception as error:
        result["error"] = str(error)
    print(json.dumps(result, indent=2))
    return 0 if result["status"] == "ok" else 1


if __name__ == "__main__":
    sys.exit(main())
