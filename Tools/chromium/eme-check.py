#!/usr/bin/env python3
"""Probe EME, MSE and codecs in a running Boaz through its authenticated loopback automation.

Turn on automation, relaunch Boaz and open any web page. The probe navigates that tab, runs the checks in the
page and prints one JSON report. Exit status 0 means every required check passed.
No license, key or session material is printed.
"""
import argparse
import base64
import json
import os
import pathlib
import socket
import struct
import sys
import time
import urllib.request

PROBE = r"""
(async () => {
  const report = {};
  const b64url = bytes => btoa(String.fromCharCode(...bytes)).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
  const types = {
    h264: 'video/mp4; codecs="avc1.42E01E"', aac: 'audio/mp4; codecs="mp4a.40.2"',
    vp9: 'video/webm; codecs="vp9"', opus: 'audio/webm; codecs="opus"',
    hevc: 'video/mp4; codecs="hvc1.1.6.L93.B0"', av1: 'video/mp4; codecs="av01.0.05M.08"',
  };
  report.mse = Object.fromEntries(Object.entries(types).map(([k, t]) => [k, MediaSource.isTypeSupported(t)]));
  report.secureContext = isSecureContext;

  const config = (robustness) => [{
    initDataTypes: ['cenc', 'keyids', 'webm'],
    videoCapabilities: [{ contentType: types.h264, robustness }],
    // Widevine caps audio at SW_SECURE_CRYPTO; robustness levels apply to video.
    audioCapabilities: [{ contentType: types.aac, robustness: robustness && 'SW_SECURE_CRYPTO' }],
  }];
  const withTimeout = (promise, ms, label) => Promise.race([promise,
    new Promise((_, reject) => setTimeout(() => reject(new Error(label + ' timed out')), ms))]);

  // Clear Key: a full license exchange with a local key, so it needs no server.
  try {
    const access = await navigator.requestMediaKeySystemAccess('org.w3.clearkey', config(''));
    const keys = await access.createMediaKeys();
    const session = keys.createSession();
    const kid = crypto.getRandomValues(new Uint8Array(16)), key = crypto.getRandomValues(new Uint8Array(16));
    const message = new Promise(resolve => session.addEventListener('message', e => resolve(e), { once: true }));
    await session.generateRequest('keyids', new TextEncoder().encode(JSON.stringify({ kids: [b64url(kid)] })));
    await withTimeout(message, 5000, 'Clear Key message');
    await session.update(new TextEncoder().encode(JSON.stringify({ keys: [{ kty: 'oct', kid: b64url(kid), k: b64url(key) }] })));
    const statuses = []; session.keyStatuses.forEach(s => statuses.push(s));
    report.clearKey = { supported: true, keyStatus: statuses[0] || null };
    await session.close();
  } catch (e) { report.clearKey = { supported: false, error: e.name + ': ' + e.message }; }

  // Widevine: access, MediaKeys (loads the CDM process) and a license challenge for a test key ID.
  report.widevine = {};
  for (const robustness of ['SW_SECURE_CRYPTO', 'SW_SECURE_DECODE', 'HW_SECURE_ALL']) {
    try {
      await navigator.requestMediaKeySystemAccess('com.widevine.alpha', config(robustness));
      report.widevine[robustness] = true;
    } catch (e) { report.widevine[robustness] = false; }
  }
  try {
    const access = await navigator.requestMediaKeySystemAccess('com.widevine.alpha', config('SW_SECURE_CRYPTO'));
    const keys = await withTimeout(access.createMediaKeys(), 15000, 'Widevine MediaKeys');
    report.widevine.mediaKeys = true;
    // pssh v0 box, Widevine system ID, protobuf { key_id: <16 bytes> }.
    const kid = crypto.getRandomValues(new Uint8Array(16));
    const data = new Uint8Array([0x12, 0x10, ...kid]);
    const systemID = [0xed, 0xef, 0x8b, 0xa9, 0x79, 0xd6, 0x4a, 0xce, 0xa3, 0xc8, 0x27, 0xdc, 0xd5, 0x1d, 0x21, 0xed];
    const size = 32 + data.length;
    const pssh = new Uint8Array([0, 0, 0, size, 0x70, 0x73, 0x73, 0x68, 0, 0, 0, 0, ...systemID,
      0, 0, 0, data.length, ...data]);
    const session = keys.createSession();
    const message = new Promise(resolve => session.addEventListener('message', e => resolve(e), { once: true }));
    await session.generateRequest('cenc', pssh);
    const event = await withTimeout(message, 15000, 'Widevine license challenge');
    report.widevine.licenseChallenge = { type: event.messageType, bytes: event.message.byteLength };
    await session.close().catch(() => {});
  } catch (e) { report.widevine.error = e.name + ': ' + e.message; }
  return JSON.stringify(report);
})()
"""

PLAYBACK = r"""
(async () => {
  // Shaka Player plays a public Widevine test stream against Google's public test license proxy.
  await new Promise((resolve, reject) => {
    const script = document.createElement('script');
    script.src = 'https://cdn.jsdelivr.net/npm/shaka-player@4.12.6/dist/shaka-player.compiled.js';
    script.onload = resolve; script.onerror = () => reject(new Error('Shaka Player did not load'));
    document.head.append(script);
  });
  shaka.polyfill.installAll();
  const video = document.createElement('video');
  video.muted = true; video.width = 640; document.body.append(video);
  const player = new shaka.Player();
  await player.attach(video);
  player.configure({ drm: { servers: { 'com.widevine.alpha': '%LICENSE%' } } });
  const report = {};
  try {
    await player.load('%MANIFEST%');
    await video.play();
    const start = video.currentTime;
    await new Promise(r => setTimeout(r, 8000));
    Object.assign(report, {
      keySystem: player.keySystem(), advanced: video.currentTime - start,
      width: video.videoWidth, height: video.videoHeight,
      decodedFrames: video.getVideoPlaybackQuality().totalVideoFrames, paused: video.paused,
    });
  } catch (e) { report.error = e.code ? 'Shaka error ' + e.code : String(e); }
  await player.destroy();
  return JSON.stringify(report);
})()
"""


class Socket:
    """Just enough RFC 6455 for one DevTools target: masked text frames out, unfragmented frames in."""

    def __init__(self, port, path, token):
        self.sock = socket.create_connection(("127.0.0.1", port), timeout=60)
        key = base64.b64encode(os.urandom(16)).decode()
        self.sock.sendall((f"GET {path} HTTP/1.1\r\nHost: 127.0.0.1:{port}\r\nUpgrade: websocket\r\n"
                           f"Connection: Upgrade\r\nSec-WebSocket-Key: {key}\r\nSec-WebSocket-Version: 13\r\n"
                           f"Authorization: Bearer {token}\r\n\r\n").encode())
        head = b""
        while b"\r\n\r\n" not in head:
            chunk = self.sock.recv(1)
            if not chunk:
                raise RuntimeError("Automation closed the WebSocket handshake")
            head += chunk
        if b" 101 " not in head.split(b"\r\n", 1)[0]:
            raise RuntimeError("Automation refused the WebSocket: " + head.split(b"\r\n", 1)[0].decode())
        self.next_id = 0

    def _read(self, count):
        data = b""
        while len(data) < count:
            chunk = self.sock.recv(count - len(data))
            if not chunk:
                raise RuntimeError("Automation closed the connection")
            data += chunk
        return data

    def call(self, method, **params):
        self.next_id += 1
        payload = json.dumps({"id": self.next_id, "method": method, "params": params}).encode()
        mask = os.urandom(4)
        length = len(payload)
        header = bytes([0x81]) + (bytes([0x80 | length]) if length < 126 else
                                  struct.pack("!BH", 0x80 | 126, length) if length < 65536 else
                                  struct.pack("!BQ", 0x80 | 127, length))
        self.sock.sendall(header + mask + bytes(b ^ mask[i % 4] for i, b in enumerate(payload)))
        while True:
            first, second = self._read(2)
            length = second & 0x7F
            if length == 126:
                length = struct.unpack("!H", self._read(2))[0]
            elif length == 127:
                length = struct.unpack("!Q", self._read(8))[0]
            message = json.loads(self._read(length)) if first & 0x0F == 1 else {}
            if message.get("id") == self.next_id:
                if "error" in message:
                    raise RuntimeError(f"{method}: {message['error'].get('message')}")
                return message["result"]


def connection(record_dir):
    records = sorted(pathlib.Path(record_dir).glob("boaz-*.json"), key=lambda p: p.stat().st_mtime)
    for path in reversed(records):
        record = json.loads(path.read_text())
        try:
            os.kill(record["pid"], 0)
            return record["port"], record["token"]
        except OSError:
            continue
    raise SystemExit(f"No running Boaz automation record in {record_dir}")


def evaluate(port, token, url, script, settle):
    """Navigate the first open Boaz tab; Boaz owns tab creation, so automation never opens or closes one."""
    request = urllib.request.Request(f"http://127.0.0.1:{port}/json/list",
                                     headers={"Authorization": f"Bearer {token}"})
    pages = [t for t in json.load(urllib.request.urlopen(request, timeout=30)) if t["type"] == "page"]
    if not pages:
        raise SystemExit("Open any web page in Boaz first; the probe runs in that tab.")
    ws = Socket(port, "/" + pages[0]["webSocketDebuggerUrl"].split("/", 3)[3], token)
    ws.call("Page.navigate", url=url)
    time.sleep(settle)
    result = ws.call("Runtime.evaluate", expression=script, awaitPromise=True, returnByValue=True)
    if "exceptionDetails" in result:
        raise RuntimeError(result["exceptionDetails"].get("text", "Page script failed"))
    return json.loads(result["result"]["value"])


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--records", required=True, help="The profile root's Automation directory")
    parser.add_argument("--page", default="https://example.com/", help="Secure page that hosts the probe")
    parser.add_argument("--playback", action="store_true", help="Also play a Widevine DASH stream in the page")
    parser.add_argument("--manifest", default="https://storage.googleapis.com/shaka-demo-assets/angel-one-widevine/dash.mpd")
    parser.add_argument("--license", default="https://cwip-shaka-proxy.appspot.com/no_auth")
    parser.add_argument("--require-widevine", action="store_true")
    args = parser.parse_args()
    port, token = connection(args.records)
    report = evaluate(port, token, args.page, PROBE, settle=3)
    if args.playback:
        script = PLAYBACK.replace("%LICENSE%", args.license).replace("%MANIFEST%", args.manifest)
        report["playback"] = evaluate(port, token, args.page, script, settle=3)
    print(json.dumps(report, indent=2))
    required = [report["mse"]["h264"], report["mse"]["aac"], report["clearKey"].get("keyStatus") == "usable"]
    if args.require_widevine:
        required += [report["widevine"].get("SW_SECURE_CRYPTO"), "licenseChallenge" in report["widevine"]]
    if args.playback:
        required += [report["playback"].get("advanced", 0) > 2]
    sys.exit(0 if all(required) else 1)


if __name__ == "__main__":
    main()
