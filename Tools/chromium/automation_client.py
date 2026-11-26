"""Client for Boaz's authenticated loopback automation (DevTools protocol), standard library only.

Turn on automation, relaunch Boaz and open any web page; callers drive that tab. Boaz owns tab creation, so the
DevTools client never opens or closes tabs; `Control` does, on a development build only.
"""
import base64
import json
import os
import pathlib
import socket
import struct
import subprocess
import time
import urllib.request


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


def attach(port, token):
    """A DevTools session on the first open Boaz tab."""
    request = urllib.request.Request(f"http://127.0.0.1:{port}/json/list",
                                     headers={"Authorization": f"Bearer {token}"})
    pages = [t for t in json.load(urllib.request.urlopen(request, timeout=30)) if t["type"] == "page"]
    if not pages:
        raise SystemExit("Open any web page in Boaz first; the checks run in that tab.")
    return Socket(port, "/" + pages[0]["webSocketDebuggerUrl"].split("/", 3)[3], token)


def run(ws, script):
    """Evaluates an async page script that resolves to a JSON string."""
    result = ws.call("Runtime.evaluate", expression=script, awaitPromise=True, returnByValue=True)
    if "exceptionDetails" in result:
        raise RuntimeError(result["exceptionDetails"].get("text", "Page script failed"))
    return json.loads(result["result"]["value"])


def evaluate(port, token, url, script, settle):
    """Navigates the first open Boaz tab to `url` and evaluates `script` there."""
    ws = attach(port, token)
    ws.call("Page.navigate", url=url)
    time.sleep(settle)
    return run(ws, script)


class Control:
    """Boaz's development-only tab control socket (Apps/macOS/Engine/AutomationControl.swift).

    It listens only in a development-channel app launched with `-BoazAutomationControl YES` while Local Automation
    runs, at `$TMPDIR/boaz-control-<pid>.sock`. One JSON line each way; a refused command raises RuntimeError.
    """

    def __init__(self, pid, timeout=30):
        directory = subprocess.check_output(["/usr/bin/getconf", "DARWIN_USER_TEMP_DIR"], text=True).strip()
        self.path = os.path.join(directory, f"boaz-control-{pid}.sock")
        self.timeout = timeout

    def wait(self, seconds=60):
        """Waits for `list` to answer: the socket follows Local Automation, and the first window follows that."""
        deadline = time.monotonic() + seconds
        while True:
            try:
                return self.list()
            except (OSError, RuntimeError):
                if time.monotonic() > deadline:
                    raise
                time.sleep(0.5)

    def call(self, command, **params):
        with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as sock:
            sock.settimeout(self.timeout)
            sock.connect(self.path)
            sock.sendall(json.dumps({"command": command, **params}).encode() + b"\n")
            data = b""
            while not data.endswith(b"\n"):
                chunk = sock.recv(65536)
                if not chunk:
                    raise RuntimeError(f"{command}: control socket closed without a reply")
                data += chunk
        reply = json.loads(data)
        if not reply.get("ok"):
            raise RuntimeError(f"{command}: {reply.get('error')}")
        return reply

    def list(self):
        """Spaces (id, profileID, name, selected), each with its pinned and Today tabs."""
        return self.call("list")["spaces"]

    def windows(self):
        """Each window: private (Incognito), selected tab, space; an Incognito window lists its tabs."""
        return self.call("list")["windows"]

    def open(self, url, space=None, private=False):
        """Opens `url` as a new Today tab in `space` (default: the current one), or with `private` as a tab in the
        Incognito window (opening one if none is open); returns the new tab's id."""
        extra = {"private": True} if private else ({"space": space} if space else {})
        return self.call("open", url=url, **extra)["tab"]

    def close_private(self):
        """Closes every Incognito window."""
        self.call("closePrivate")

    def select(self, tab):
        self.call("select", tab=tab)

    def close(self, tab):
        self.call("close", tab=tab)

    def quit(self):
        """Quits the way Cmd-Q does, so the next launch restores the saved windows."""
        self.call("quit")
