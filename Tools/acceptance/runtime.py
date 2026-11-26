"""Runtime acceptance for the Chromium DMG (PLAN-02 rows 2-4) on a throwaway Mac (a CI runner): it replaces
/Applications/Boaz.app and the current user's Boaz data. Pages are driven through Boaz's own opt-in Local
Automation (authenticated DevTools protocol on 127.0.0.1); native steps (tabs with ⌘T, menus, extensions UI) by
BoazAcceptanceUITests.

  runtime.py <Boaz.dmg> <output dir> [check ...]     checks: menus, reopen (with the probe), webstore, unpacked, profiles, private,
                                                     passwords (default: all)

COHORT=all installs all 8 cohort extensions from the live Chrome Web Store; otherwise only uBlock Origin Lite.
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
import hashlib  # noqa: E402

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
SECOND = 'acceptance-b'
# This run's test password for the fixture's sign-in form; it is never written to the results.
PASSWORD = 'pw' + uuid.uuid4().hex


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
    """Every page load since `since` ran in Chromium, and no request at all told the site it was Safari (must-have
    #1). Page loads are told apart by their Fetch Metadata: Boaz's icon fetch (URLSession) requests pages too."""
    since_then = [entry for entry in run.logged() if entry['time'] >= since]
    pages = [entry for entry in since_then if entry.get('mode') == 'navigate' and entry.get('dest') == 'document']
    webkit = sorted({entry['path'] for entry in since_then if WEBKIT_AGENT.search(entry['agent'])})
    run.check(bool(pages) and not webkit,
              f'{label}: all {len(pages)} page loads used Chromium' if not webkit else
              f'{label}: requests for {", ".join(webkit)} presented as Safari (must-have #1, #191)')


def probe(run):
    """What this runner allows; decides which checks can be automated."""
    run.heading('Probe')
    port_token = automation()
    if not run.check(port_token is not None, 'Local Automation published its record'):
        return None
    port, token = port_token
    pages = sorted((t for t in targets(port, token) if t['type'] == 'page'), key=lambda t: not t['url'].startswith(SITE))
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
    # Tabs, as a person opens them (⌘T): a link from another app opens in a Quick Window, which isn't kept.
    native(run, 'testOpenTabs', BOAZ_ACCEPTANCE_URLS=','.join(SITE + p for p in paths))
    time.sleep(5)
    run.check(all(any(e['path'] == p for e in run.logged()) for p in paths), 'Boaz opened all 3 fixture tabs')
    agents_check(run, since, 'opened tabs')
    probe(run)
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


# The ledger's extension cohort (parity.md E1/E2), by Chrome Web Store ID.
COHORT = {
    'ddkjiahejlhfcafbddmgiahcphecmpfh': 'uBlock Origin Lite',
    'aeblfdkhhhdcdjpifhhbdiojplfjncoa': '1Password',
    'nngceckbapebfimnlniiiahkandclblb': 'Bitwarden',
    'eimadpbcbfnmbkopoojfekhnkhdbieeh': 'Dark Reader',
    'fmkadmapgofadopljbjfkapdkoienihi': 'React Developer Tools',
    'nhdogjmejiglipccpnnnanhbledajbpd': 'Vue.js devtools',
    'kbfnbcaeplbcioakkpcpgfkobkghlhen': 'Grammarly',
    'gppongmhjkpfnbhagpmjfkannfbllamg': 'Wappalyzer',
}


def profile_dir(profile_id='default'):
    return CHROMIUM / ('Boaz-' + hashlib.sha256(profile_id.encode()).hexdigest().upper())


def extension_settings(profile_id='default'):
    """extensions.settings from the profile's Preferences and Secure Preferences, merged."""
    merged = {}
    for name in ('Preferences', 'Secure Preferences'):
        path = profile_dir(profile_id) / name
        if path.exists():
            merged.update(json.loads(path.read_text()).get('extensions', {}).get('settings', {}))
    return merged


def native(run, test, **environment):
    """Runs one BoazAcceptanceUITests step against the installed, running Boaz; its result bundle goes in `out`."""
    extra = [f'{key}={value}' for key, value in environment.items()]
    result = subprocess.run(['make', '-C', str(HERE.parent.parent), 'acceptance-uitest', f'TEST={test}',
                             f'BOAZ_ACCEPTANCE_APP={APP}', *extra], capture_output=True, text=True)
    (run.out / f'{test}.log').write_text(result.stdout + result.stderr)
    bundle = HERE.parent.parent / f'build/Acceptance-{test}.xcresult'
    kept = run.out / bundle.name
    shutil.rmtree(kept, ignore_errors=True)
    if bundle.exists():
        shutil.copytree(bundle, kept)
    return result.returncode == 0


def failures(run, test):
    """The failure messages in the last run of `test`, from its result bundle (a test's own output isn't in the log)."""
    result = subprocess.run(['xcrun', 'xcresulttool', 'get', 'test-results', 'tests', '--path',
                             str(run.out / f'Acceptance-{test}.xcresult')], capture_output=True, text=True)
    messages = []

    def walk(node):
        if node.get('nodeType') == 'Failure Message':
            messages.append(node.get('name', ''))
        for child in node.get('children', []):
            walk(child)
    try:
        for node in json.loads(result.stdout)['testNodes']:
            walk(node)
    except (ValueError, KeyError):
        return ['no readable result bundle']
    return messages


def menus(run):
    """Row 4, must-have #1: no menu names WebKit or a browser engine."""
    run.heading('No engine in the UI')
    run.check(native(run, 'testMenusNameNoEngine'), 'no menu names WebKit or a browser engine (XCUITest, by path)')


STORE = 'https://chromewebstore.google.com/detail/{id}'
# The store's own "Add to Chrome" button, scrolled into view: where a trusted click lands, and whether anything (a
# store promo, say) covers it there. Nothing on the page is clicked through: a covered button is reported.
STORE_BUTTON = """Promise.resolve(JSON.stringify((() => {
  const button = [...document.querySelectorAll('button, [role="button"]')].find(b => /add to chrome/i.test(b.textContent)
    && !b.disabled && b.getClientRects().length);
  if (!button) return null;
  button.scrollIntoView({block: 'center'});
  const r = button.getBoundingClientRect(), x = r.left + r.width / 2, y = r.top + r.height / 2;
  const hit = document.elementFromPoint(x, y);
  return {x, y, covered: !(hit && button.contains(hit))};
})()))"""


def store_click(run, port, token, id):
    """Opens the extension's store page as a tab and clicks its button with a trusted mouse event, 3 tries:
    'clicked', 'covered' or None (the store didn't answer with the button: inconclusive)."""
    url = STORE.format(id=id)
    result = None
    for attempt in range(1, 4):
        native(run, 'testOpenTabs', BOAZ_ACCEPTANCE_URLS=url)
        end = time.time() + 30
        while time.time() < end:
            try:
                page = next((t for t in targets(port, token) if t['type'] == 'page' and t['url'].startswith(url)), None)
                found = page and automation_client.run(target_socket(port, token, page), STORE_BUTTON)
                if found and not found['covered']:
                    socket = target_socket(port, token, page)
                    for kind in ('mousePressed', 'mouseReleased'):
                        socket.call('Input.dispatchMouseEvent', type=kind, x=found['x'], y=found['y'],
                                    button='left', clickCount=1)
                    return 'clicked'
                result = 'covered' if found else result
            except Exception as error:  # the page navigating mid-call; the next poll retries
                run.note(f'store page {COHORT[id]}, try {attempt}: {error}')
            time.sleep(2)
        run.shot(f'store-{id}-try-{attempt}')
    return result


def webstore(run):
    """Row 3, part A: live Chrome Web Store installs through the store's own button and Boaz's sheet."""
    run.heading('Chrome Web Store installs')
    ids = list(COHORT) if os.environ.get('COHORT') == 'all' else ['ddkjiahejlhfcafbddmgiahcphecmpfh']
    if not boaz_pids():
        launch()
        automation()
        time.sleep(5)
    port_token = automation()
    if not run.check(port_token is not None, 'Local Automation published its record'):
        return
    reached = []
    for id in ids:
        clicked = store_click(run, *port_token, id)
        if clicked is None:
            run.check(False, f'inconclusive: store unreachable for {COHORT[id]} (infra: re-run to settle)')
            continue
        if not run.check(clicked == 'clicked', f'{COHORT[id]}: clicked the store\'s Add to Chrome button'
                         + ('' if clicked == 'clicked' else ' (something on the page covers it)')):
            continue
        reached.append(id)
        run.check(native(run, 'testWebStoreInstallSheet', BOAZ_ACCEPTANCE_EXTENSIONS=id),
                  f'{COHORT[id]}: Boaz\'s sheet, the confirmation, the toolbar button and the popup (XCUITest)'
                  + ''.join(f'; {m}' for m in failures(run, 'testWebStoreInstallSheet')))
    time.sleep(5)
    settings = extension_settings()
    workers = {t['url'].split('/')[2] for t in targets(*port_token) if t['type'] == 'service_worker'
               and t['url'].startswith('chrome-extension://')}
    for id in reached:
        entry = settings.get(id, {})
        version = entry.get('manifest', {}).get('version') or entry.get('version', '?')
        run.check(entry.get('state', 1) == 1 and entry.get('from_webstore') is True and not entry.get('disable_reasons'),
                  f'{COHORT[id]} {version}: enabled, from the Web Store')
        run.check(id in workers, f'{COHORT[id]}: its service worker is running')
    quit_app(run, 'webstore')
    launch()
    port_token = automation()
    time.sleep(8)
    workers = {t['url'].split('/')[2] for t in targets(*port_token) if t['type'] == 'service_worker'} if port_token else set()
    settings = extension_settings()
    for id in reached:
        run.check(id in settings and id in workers, f'{COHORT[id]}: still installed and running after a relaunch')


def second_profile(run):
    """A second profile with its space, Acceptance B, added to the library while Boaz is quit; Boaz is left running."""
    with sqlite3.connect(SUPPORT / 'boaz.sqlite') as db:
        exists = db.execute('SELECT 1 FROM profile WHERE id = ?', (SECOND,)).fetchone()
    if not exists:
        if boaz_pids():
            quit_app(run, 'before-second-profile')
        added = subprocess.run([sys.executable, str(HERE / 'library.py'), 'add-profile', str(SUPPORT / 'boaz.sqlite'),
                                SECOND, 'Acceptance B'], capture_output=True, text=True)
        if not run.check(added.returncode == 0, 'added a second profile with its space'):
            run.note(added.stderr[-500:])
            return False
    if not boaz_pids():
        launch()
        automation()
        time.sleep(5)
    return True


def first_space():
    with sqlite3.connect(SUPPORT / 'boaz.sqlite') as db:
        return db.execute('SELECT space.title FROM space JOIN profile ON profile.id = space.profileID WHERE '
                          'profile.isDefault = 1 AND space.deletedAt IS NULL ORDER BY space.position LIMIT 1').fetchone()[0]


def rows(path, sql):
    """`sql` on a copy of a Chromium database (it may hold an exclusive lock); None when there's no such file."""
    if not path.exists():
        return None
    with tempfile.TemporaryDirectory() as folder:
        for suffix in ('', '-wal', '-journal'):
            if os.path.exists(f'{path}{suffix}'):
                shutil.copy(f'{path}{suffix}', f'{folder}/db{suffix}')
        with sqlite3.connect(f'{folder}/db') as db:
            return db.execute(sql).fetchall()


def cookies_sent(run, path, since=0):
    """Cookies of the page loads of `path`, told apart by their Fetch Metadata whatever the user agent: Boaz's icon
    fetch (URLSession, #191) requests the page too, without the cookies or those headers."""
    return [entry['cookie'] for entry in run.logged() if entry['path'] == path and entry['time'] >= since
            and entry.get('mode') == 'navigate' and entry.get('dest') == 'document']


def unpacked_id(folder):
    """Chromium's ID for an unpacked extension without a key: the first 128 bits of SHA-256 of its path, as a-p."""
    return ''.join(chr(97 + int(c, 16)) for c in hashlib.sha256(str(folder).encode()).hexdigest()[:32])


def unpacked(run):
    """Row 3, part B: the cohort's store CRXs, loaded unpacked with their store keys in a second profile, plus the
    parity fixture: controls, shortcut, side panel, workers, functions, isolation and a relaunch."""
    run.heading('Extensions loaded unpacked, in a second profile')
    folder = run.out / 'cohort'
    prepared = subprocess.run([sys.executable, str(HERE / 'cohort.py'), str(folder), *COHORT],
                              capture_output=True, text=True)
    run.note('cohort CRXs (update2, this run): ' + prepared.stdout.replace('\n', '; ').strip('; '))
    if not run.check(prepared.returncode == 0, 'downloaded every cohort CRX, its key matching its store ID'):
        run.note(prepared.stderr[-500:])
        return
    fixture = (run.out / 'parity-extension').resolve()
    shutil.copytree(HERE.parent / 'chromium/fixtures/parity-extension', fixture, dirs_exist_ok=True)
    fixture_id = unpacked_id(fixture)
    if not second_profile(run):
        return
    run.check(native(run, 'testSwitchSpace', BOAZ_ACCEPTANCE_SPACE='Acceptance B'), 'switched to the second profile\'s space')
    folders = [str((folder / id).resolve()) for id in COHORT] + [str(fixture)]
    run.check(native(run, 'testLoadUnpacked', BOAZ_ACCEPTANCE_UNPACKED=','.join(folders)),
              'chrome://extensions → Developer mode → Load unpacked, for all 9 (XCUITest)')
    time.sleep(5)
    settings, default = extension_settings(SECOND), extension_settings()
    for id in [*COHORT, fixture_id]:
        name = COHORT.get(id, 'parity fixture')
        entry = settings.get(id, {})
        run.check(entry.get('location') == 4 and not entry.get('disable_reasons'),
                  f'{name}: loaded unpacked and enabled in the second profile, under its store ID')
        run.check(default.get(id, {}).get('location') != 4, f'{name}: not in the first profile')
    port_token = automation()
    workers = {t['url'].split('/')[2] for t in targets(*port_token) if t['type'] == 'service_worker'} if port_token else set()
    for id in [*COHORT, fixture_id]:
        if (settings.get(id, {}).get('manifest', {}).get('background') or {}).get('service_worker'):
            run.check(id in workers, f'{COHORT.get(id, "parity fixture")}: its MV3 service worker is running')
    run.check(native(run, 'testExtensionControls', BOAZ_ACCEPTANCE_EXTENSIONS=','.join([*COHORT, fixture_id]),
                     BOAZ_ACCEPTANCE_FIXTURE=fixture_id),
              'pin, popup and unpin for all 9; the fixture\'s shortcut and side panel (XCUITest)')

    native(run, 'testOpenTabs', BOAZ_ACCEPTANCE_URLS=f'{SITE}/functions,https://example.com/')
    time.sleep(8)
    if port_token:
        pages = {t['url']: t for t in targets(*port_token) if t['type'] == 'page'}
        page = pages.get(f'{SITE}/functions')
        if run.check(page is not None, 'the functions page is open in the second profile'):
            seen = automation_client.run(target_socket(*port_token, page), """new Promise(r => setTimeout(r, 3000))
                .then(() => JSON.stringify({
                  react: typeof window.__REACT_DEVTOOLS_GLOBAL_HOOK__ === 'object',
                  vue: typeof window.__VUE_DEVTOOLS_GLOBAL_HOOK__ === 'object',
                  ad: window.adLoaded,
                  darkReader: !!document.querySelector('style.darkreader, meta[name="darkreader"]'),
                  grammarly: ['data-gr-ext-installed', 'data-new-gr-c-s-check-loaded'].some(a =>
                    document.documentElement.hasAttribute(a) || document.body.hasAttribute(a))
                    || !!document.querySelector('grammarly-desktop-integration'),
                }))""")
            run.note(f'functions page: {seen}')
            run.check(seen['ad'] is False, 'uBlock Origin Lite: the known ad script was blocked')
            run.check(seen['darkReader'], 'Dark Reader: restyled the page')
            run.check(seen['react'], 'React Developer Tools: its hook is in the page')
            run.check(seen['vue'], 'Vue.js devtools: its hook is in the page')
            run.check(seen['grammarly'], 'Grammarly: its content script marked the page')
        example = pages.get('https://example.com/')
        if example:
            marked = automation_client.run(target_socket(*port_token, example),
                                           'Promise.resolve(JSON.stringify(document.documentElement.dataset.boazParity || null))')
            run.check(marked == 'content-script', 'parity fixture: its content script ran on example.com')

    quit_app(run, 'unpacked')
    launch()
    port_token = automation()
    time.sleep(10)
    settings = extension_settings(SECOND)
    workers = {t['url'].split('/')[2] for t in targets(*port_token) if t['type'] == 'service_worker'} if port_token else set()
    kept = [id for id in [*COHORT, fixture_id] if settings.get(id, {}).get('location') == 4]
    run.check(len(kept) == 9, f'after a relaunch, {len(kept)} of 9 are still installed in the second profile')
    run.note(f'after a relaunch, {len(workers & set(kept))} of them have a running worker')


def profiles(run):
    """Row 2: the second profile's sign-in and history stay out of the first; each restores its own tabs."""
    run.heading('Profile isolation')
    if not second_profile(run):
        return
    first = first_space()
    marker = f'history-b-{uuid.uuid4().hex}'
    native(run, 'testSwitchSpace', BOAZ_ACCEPTANCE_SPACE='Acceptance B')
    native(run, 'testOpenTabs', BOAZ_ACCEPTANCE_URLS=f'{SITE}/set?profile=b,{SITE}/{marker},{SITE}/whoami?profile=b')
    native(run, 'testSwitchSpace', BOAZ_ACCEPTANCE_SPACE=first)
    native(run, 'testOpenTabs', BOAZ_ACCEPTANCE_URLS=f'{SITE}/whoami?profile=a')
    time.sleep(3)
    b, a = cookies_sent(run, '/whoami?profile=b'), cookies_sent(run, '/whoami?profile=a')
    run.check(any('boaz_session=' in c for c in b), 'the second profile signs in on the fixture site (control)')
    run.check(bool(a) and not any('boaz_session=' in c for c in a), 'the first profile is not sent the second\'s sign-in')
    quit_app(run, 'profiles')

    query = "SELECT name FROM cookies WHERE host_key LIKE '%127.0.0.1%'"
    b_disk, a_disk = rows(profile_dir(SECOND) / 'Network/Cookies', query) or [], rows(profile_dir() / 'Network/Cookies', query) or []
    run.check(('boaz_session',) in b_disk and ('boaz_session',) not in a_disk,
              'on disk, the sign-in cookie is in the second profile\'s cookie store only')
    with sqlite3.connect(SUPPORT / 'boaz.sqlite') as db:
        owners = {row[0] for row in db.execute('SELECT profileID FROM historyVisit WHERE url LIKE ?', (f'%{marker}%',))}
        tabs = {}
        for profile, url in db.execute("SELECT profileID, url FROM sidebarItem WHERE kind = 'tab' AND deletedAt IS NULL"):
            tabs.setdefault(profile, set()).add(url)
    run.check(owners == {SECOND}, f'Boaz\'s history has the second profile\'s visit under it only ({sorted(owners)})')
    history = rows(profile_dir() / 'History', 'SELECT url FROM urls') or []
    run.check(not any(marker in url for (url,) in history), 'the first profile\'s Chromium history doesn\'t have it')
    holders = {profile for profile, urls in tabs.items() if f'{SITE}/whoami?profile=a' in urls}
    run.check(f'{SITE}/{marker}' in tabs.get(SECOND, set()) and bool(holders) and SECOND not in holders,
              'the library keeps each profile\'s tabs under that profile')

    since = time.time()
    launch()
    automation()
    time.sleep(8)
    native(run, 'testSwitchSpace', BOAZ_ACCEPTANCE_SPACE='Acceptance B')
    time.sleep(5)
    native(run, 'testSwitchSpace', BOAZ_ACCEPTANCE_SPACE=first)
    time.sleep(3)
    b, a = cookies_sent(run, '/whoami?profile=b', since), cookies_sent(run, '/whoami?profile=a', since)
    run.note(f'after a relaunch, {len(a)} and {len(b)} loads of the first and second profile\'s front tabs')
    run.check(bool(b) and all('boaz_session=' in c for c in b) and bool(a) and not any('boaz_session=' in c for c in a),
              'after a relaunch, both profiles restore their tabs, each with its own cookies')


TRACE_PLACES = [SUPPORT, HOME / f'Library/Caches/{ID}', HOME / f'Library/HTTPStorages/{ID}', HOME / f'Library/WebKit/{ID}',
                HOME / f'Library/Saved Application State/{ID}.savedState', PREFS.parent / f'{ID}.plist']


def traces(token):
    """Files under Boaz's data that contain `token` (UTF-8 or UTF-16)."""
    needles = [token.encode(), token.encode('utf-16-le')]
    found = []
    for place in TRACE_PLACES:
        for path in ([place] if place.is_file() else place.rglob('*') if place.exists() else []):
            if not path.is_file() or path.is_symlink():
                continue
            with path.open('rb') as file:
                tail = b''
                while chunk := file.read(1 << 20):
                    if any(needle in tail + chunk for needle in needles):
                        found.append(str(path.relative_to(HOME)))
                        break
                    tail = chunk[-64:]
    return found


def private(run):
    """Row 2: a private window leaves nothing on disk, shares no cookie with the next one and offers no password save."""
    run.heading('Private windows')
    if not boaz_pids():
        launch()
        automation()
        time.sleep(5)
    token = uuid.uuid4().hex
    native(run, 'testOpenPrivateTabs', BOAZ_ACCEPTANCE_URLS=','.join(
        [f'{SITE}/set?private=1', f'{SITE}/private-{token}', f'{SITE}/whoami?private=1', f'{SITE}/login?private=1']))
    run.check(native(run, 'testPasswordPrompt', BOAZ_ACCEPTANCE_LOGIN=f'private-{token}:{PASSWORD}',
                     BOAZ_ACCEPTANCE_EXPECT_PROMPT='0'), 'no offer to save a password typed in a private window (XCUITest)')
    native(run, 'testClosePrivateWindows')
    native(run, 'testOpenPrivateTabs', BOAZ_ACCEPTANCE_URLS=f'{SITE}/whoami?private=2')
    native(run, 'testClosePrivateWindows')
    first, second = cookies_sent(run, '/whoami?private=1'), cookies_sent(run, '/whoami?private=2')
    run.check(any('boaz_session=' in c for c in first), 'a private window signs in on the fixture site (control)')
    run.check(bool(second) and not any('boaz_session=' in c for c in second),
              'the next private window is not sent the closed one\'s sign-in')
    run.check(any(e['path'] == '/signed-in' for e in run.logged()), 'the private login form submitted')
    quit_app(run, 'private')
    found = traces(token) + traces(PASSWORD)
    run.check(not found, 'nothing in Boaz\'s data names the private pages, the sign-in or the password'
              + (f': {", ".join(found)}' if found else ''))


def passwords(run):
    """Row 2, P3: the runner probe for Boaz's save offer, and Chromium's own password stores staying empty."""
    run.heading('Passwords')
    if not boaz_pids():
        launch()
        automation()
        time.sleep(5)
    since = time.time()
    native(run, 'testOpenTabs', BOAZ_ACCEPTANCE_URLS=f'{SITE}/login')
    shown = native(run, 'testPasswordPrompt', BOAZ_ACCEPTANCE_LOGIN=f'acceptance:{PASSWORD}', BOAZ_ACCEPTANCE_EXPECT_PROMPT='1')
    problems = [m for m in failures(run, 'testPasswordPrompt') if 'No save offer' not in m]
    run.check(not problems, 'signed in on the login page (XCUITest)' + ''.join(f'; {m}' for m in problems))
    run.check(any(e['path'] == '/signed-in' and e['time'] >= since for e in run.logged()), 'the login form submitted')
    if shown:
        run.note('P3 probe: Boaz offered to save the sign-in on this runner, so the offer (and none in private) is '
                 'automated. Saving needs Touch ID or the login password, so Save, fill and iCloud sync stay manual.')
    else:
        run.note('P3 probe: no save offer on this runner, so P3 stays manual.')
    quit_app(run, 'passwords')
    # Boaz keeps passwords in its own Keychain store; Chromium's must stay empty. Its account store isn't guarded by
    # Boaz's password patches (architect-03, on 157 and 159), so it must stay unused: no Google sign-in.
    for profile, label in (('default', 'first profile'), (SECOND, 'second profile')):
        for name in ('Login Data', 'Login Data For Account'):
            saved = rows(profile_dir(profile) / name, 'SELECT origin_url FROM logins')
            run.check(not saved, f'{label}: Chromium\'s {name} has no saved logins '
                      f'({"no file" if saved is None else f"{len(saved)} rows"})')
        path = profile_dir(profile) / 'Preferences'
        preferences = json.loads(path.read_text()) if path.exists() else {}
        services = preferences.get('google', {}).get('services', {})
        accounts = [a.get('email', '?') for a in preferences.get('account_info', [])]
        run.check(not accounts and not services.get('last_gaia_id') and not services.get('last_signed_in_username'),
                  f'{label}: no Google account signed in to Chromium ({len(accounts)} accounts)')


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
        launch()
        automation()
        time.sleep(5)
        steps = {'menus': menus, 'reopen': reopen, 'webstore': webstore, 'unpacked': unpacked,
                 'profiles': profiles, 'private': private, 'passwords': passwords}
        for check in checks or steps:
            {'probe': probe, **steps}[check](run)
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
