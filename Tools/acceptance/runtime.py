"""Runtime acceptance for the Chromium DMG (PLAN-02 rows 2-4) on a throwaway Mac (a CI runner): it replaces
/Applications/Boaz.app and the current user's Boaz data. Pages are driven through Boaz's own opt-in Local
Automation (authenticated DevTools protocol on 127.0.0.1); tabs are opened with `open -a`, as another app would.

  runtime.py <Boaz.dmg> <output dir> [check ...]     checks: probe, reopen (default: all)
"""
import json
import os
import pathlib
import plistlib
import re
import shutil
import sqlite3
import subprocess
import sys
import tempfile
import time
import urllib.request
import uuid

HERE = pathlib.Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent / 'chromium'))
import automation_client  # noqa: E402

ID = 'com.chenkahana.boaz'
APP = pathlib.Path('/Applications/Boaz.app')
HOME = pathlib.Path.home()
SUPPORT = HOME / 'Library/Application Support/Boaz'
CHROMIUM = SUPPORT / 'Chromium'
PREFS = HOME / f'Library/Preferences/{ID}'
PORT = 8766
SITE = f'http://127.0.0.1:{PORT}'
# Chromium's user agent names Chrome; WebKit's ends in Safari's (must-have #1: every page runs in Chromium).
WEBKIT_AGENT = re.compile(r'Version/[0-9.]+ Safari/')


class Run:
    def __init__(self, out):
        self.out = out
        self.failed = False
        self.results = out / 'results.md'
        self.results.write_text('')
        self.requests = out / 'requests.jsonl'

    def note(self, text):
        print(text, flush=True)
        with self.results.open('a') as results:
            results.write(f'- {text}\n')

    def check(self, ok, text):
        self.note(('PASS ' if ok else 'FAIL ') + text)
        self.failed |= not ok
        return ok

    def heading(self, text):
        with self.results.open('a') as results:
            results.write(f'## {text}\n')

    def shot(self, name):
        subprocess.run(['screencapture', '-x', str(self.out / f'{name}.png')], check=False)

    def logged(self):
        if not self.requests.exists():
            return []
        return [json.loads(line) for line in self.requests.read_text().splitlines() if line.strip()]


def wait(seconds, condition, step=0.5):
    end = time.time() + seconds
    while time.time() < end:
        value = condition()
        if value:
            return value
        time.sleep(step)
    return None


def boaz_pids():
    found = subprocess.run(['pgrep', '-f', f'{APP}/Contents/'], capture_output=True, text=True).stdout.split()
    return [int(pid) for pid in found]


def install(run, dmg):
    mount = tempfile.mkdtemp()
    subprocess.run(['hdiutil', 'attach', '-nobrowse', '-readonly', '-noautoopen', '-mountpoint', mount, dmg],
                   check=True, stdout=subprocess.DEVNULL)
    shutil.rmtree(APP, ignore_errors=True)
    subprocess.run(['ditto', f'{mount}/Boaz.app', str(APP)], check=True)
    subprocess.run(['hdiutil', 'detach', '-quiet', mount], check=False)
    info = plistlib.loads((APP / 'Contents/Info.plist').read_bytes())
    run.note(f"Installed Boaz {info['CFBundleShortVersionString']} ({info['CFBundleVersion']})")


def defaults(*arguments):
    subprocess.run(['defaults', 'write', str(PREFS), *arguments], check=True)


def launch(*urls):
    subprocess.run(['open', '-a', str(APP), *urls], check=True)


def quit_app(run, label, limit=10):
    """Quits the way the Dock and Cmd-Q do (AppKit's terminate), then checks nothing is left behind."""
    subprocess.run([str(run.out / 'quit'), ID], check=False)
    gone = wait(limit, lambda: not boaz_pids())
    if not gone:
        run.shot(f'quit-stuck-{label}')
        for pid in boaz_pids()[:1]:
            subprocess.run(['sample', str(pid), '3', '-file', str(run.out / f'quit-sample-{label}.txt')],
                           check=False, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        subprocess.run(['pkill', '-9', '-f', f'{APP}/Contents/'], check=False)
        time.sleep(2)
    run.check(bool(gone), f'{label}: Boaz and all its helpers exit within {limit} s of quitting')
    lock = CHROMIUM / 'SingletonLock'
    run.check(not os.path.lexists(lock), f'{label}: no SingletonLock left')


def automation():
    """Port and token of the running Boaz's automation, once it has published them."""
    def record():
        try:
            return automation_client.connection(CHROMIUM / 'Automation')
        except SystemExit:
            return None
    return wait(60, record)


def targets(port, token):
    request = urllib.request.Request(f'http://127.0.0.1:{port}/json/list',
                                     headers={'Authorization': f'Bearer {token}'})
    return json.load(urllib.request.urlopen(request, timeout=30))


def target_socket(port, token, target):
    return automation_client.Socket(port, '/' + target['webSocketDebuggerUrl'].split('/', 3)[3], token)


def library_urls():
    db = SUPPORT / 'boaz.sqlite'
    if not db.exists():
        return set()
    with sqlite3.connect(db) as connection:
        return {row[0] for row in connection.execute(
            "SELECT url FROM sidebarItem WHERE kind = 'tab' AND deletedAt IS NULL AND url IS NOT NULL")}


def agents_check(run, since, label):
    """Every request since `since` came from Chromium (must-have #1)."""
    seen = [entry for entry in run.logged() if entry['time'] >= since and entry['path'] != '/favicon.ico']
    webkit = sorted({entry['path'] for entry in seen if WEBKIT_AGENT.search(entry['agent'])})
    run.check(bool(seen) and not webkit,
              f'{label}: all {len(seen)} page requests used Chromium' if not webkit else
              f'{label}: WebKit loaded {", ".join(webkit)} (must-have #1, #191)')


def probe(run):
    """What this runner allows; decides which checks can be automated."""
    run.heading('Probe')
    port_token = automation()
    if not run.check(port_token is not None, 'Local Automation published its record'):
        return None
    port, token = port_token
    pages = [t for t in targets(port, token) if t['type'] == 'page']
    run.check(bool(pages), f'Automation lists {len(pages)} page targets')
    run.note('targets: ' + ', '.join(sorted(t['url'] for t in targets(port, token))))
    if pages:
        ws = target_socket(port, token, pages[0])
        agent = automation_client.run(ws, 'Promise.resolve(JSON.stringify(navigator.userAgent))')
        run.note(f'probe: the page reports user agent {agent}')
        media = automation_client.run(ws, '''navigator.mediaDevices.enumerateDevices()
            .then(d => JSON.stringify(d.map(x => x.kind))).catch(e => JSON.stringify(String(e)))''')
        run.note(f'probe: media devices visible to a page: {media}')
    return port, token


def reopen(run):
    """Row 4: quit and reopen restore the window and tabs with no profile picker; quit with a popup open."""
    run.heading('Reopen and quit')
    paths = [f'/reopen/{n}' for n in range(1, 4)]
    since = time.time()
    for path in paths:
        launch(SITE + path)
        wait(30, lambda: any(e['path'] == path for e in run.logged()))
    time.sleep(5)
    run.check(all(any(e['path'] == p for e in run.logged()) for p in paths), 'Boaz opened all 3 fixture tabs')
    agents_check(run, since, 'opened tabs')
    run.shot('reopen-before')
    quit_app(run, 'reopen')
    kept = {SITE + p for p in paths} & library_urls()
    run.check(len(kept) == 3, f'the library keeps the 3 tabs ({len(kept)} found)')
    since = time.time()
    launch()
    port_token = automation()
    if not run.check(port_token is not None, 'reopened Boaz published its automation record'):
        return
    port, token = port_token
    time.sleep(8)
    run.shot('reopen-after')
    listed = targets(port, token)
    urls = [t['url'] for t in listed]
    run.check(not any('profile-picker' in url for url in urls), 'no Chromium profile picker on reopen')
    restored = [url for url in urls if url.startswith(SITE + '/reopen/')]
    run.check(bool(restored), f'reopen restored the window with a fixture tab ({len(restored)} live)')
    agents_check(run, since, 'restored tabs')

    # Quit with a window.open popup focused (6bcb542).
    pages = [t for t in listed if t['type'] == 'page' and t['url'].startswith(SITE)]
    if pages:
        ws = target_socket(port, token, pages[0])
        ws.call('Runtime.evaluate', expression=f"window.open('{SITE}/popup', 'boaz', 'width=400,height=300')",
                userGesture=True)
        wait(20, lambda: any(e['path'] == '/popup' for e in run.logged()))
        run.check(any(e['path'] == '/popup' for e in run.logged()), 'a page opened a popup window')
        time.sleep(2)
        run.shot('popup-open')
    quit_app(run, 'popup-quit')


def main():
    dmg, out, *checks = sys.argv[1:]
    out = pathlib.Path(out)
    out.mkdir(parents=True, exist_ok=True)
    run = Run(out)
    subprocess.run(['swiftc', '-O', '-o', str(out / 'quit'), '-'], check=True, text=True, input=(
        'import AppKit\nfor app in NSRunningApplication.runningApplications(withBundleIdentifier: '
        'CommandLine.arguments[1]) { _ = app.terminate() }\n'))
    server = subprocess.Popen([sys.executable, str(HERE / 'fixture_server.py'), str(PORT), 's' + uuid.uuid4().hex,
                               'p' + uuid.uuid4().hex, 'c' + uuid.uuid4().hex, str(run.requests)])
    try:
        install(run, dmg)
        defaults('onboardingCompleted', '-bool', 'YES')
        defaults('SUEnableAutomaticChecks', '-bool', 'NO')
        defaults('boaz.chromium.automation.enabled', '-bool', 'YES')
        launch(SITE + '/probe')
        wait(60, lambda: any(e['path'] == '/probe' for e in run.logged()))
        for check in checks or ['probe', 'reopen']:
            {'probe': probe, 'reopen': reopen}[check](run)
        if boaz_pids():
            quit_app(run, 'end')
    finally:
        server.terminate()
        log = subprocess.run(['log', 'show', '--last', '30m', '--info', '--predicate', f'subsystem == "{ID}"'],
                             capture_output=True, text=True).stdout
        (out / 'boaz.log').write_text(log)
    sys.exit(1 if run.failed else 0)


if __name__ == '__main__':
    main()
