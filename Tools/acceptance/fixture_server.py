"""Local site for the upgrade acceptance run: /set and /cold sign in with cookies, /whoami logs what the browser sends back,
/login is a sign-in form.

Usage: fixture_server.py <port> <session value> <plain value> <cold value> <log.jsonl>
"""
import http.server
import json
import sys
import time

PORT, SESSION, PLAIN, COLD, LOG = int(sys.argv[1]), sys.argv[2], sys.argv[3], sys.argv[4], sys.argv[5]
YEAR = 365 * 24 * 3600


class Handler(http.server.BaseHTTPRequestHandler):
    def do_POST(self):
        self.rfile.read(int(self.headers.get('Content-Length') or 0))
        self.do_GET()

    def do_GET(self):
        with open(LOG, 'a') as log:
            log.write(json.dumps({'time': time.time(), 'path': self.path,
                                  'cookie': self.headers.get('Cookie', ''),
                                  'agent': self.headers.get('User-Agent', '')}) + '\n')
        page = self.path.split('?')[0]
        if page == '/set':
            body = (f'<title>Boaz fixture sign-in</title><p>Signed in.</p>'
                    f'<script>localStorage.setItem("boaz_local", "{PLAIN}")</script>')
            cookies = [f'boaz_session={SESSION}; Max-Age={YEAR}; Path=/; HttpOnly; SameSite=Lax',
                       f'boaz_plain={PLAIN}; Max-Age={YEAR}; Path=/']
        elif page == '/cold':
            body = '<title>Boaz fixture cold sign-in</title><p>Signed in from a link.</p>'
            cookies = [f'boaz_cold={COLD}; Max-Age={YEAR}; Path=/; HttpOnly; SameSite=Lax']
        elif page == '/functions':
            # What the extension cohort acts on: a known ad script, a light page, a text area.
            body = ('<title>Boaz fixture functions</title><style>body { background: #ffffff; color: #000000 }</style>'
                    '<p>Extension checks.</p><textarea id="text" rows="4" cols="40">Their is a mistake here.</textarea>'
                    '<script>window.adLoaded = null;</script>'
                    '<script src="https://pagead2.googlesyndication.com/pagead/js/adsbygoogle.js" '
                    'onload="window.adLoaded = true" onerror="window.adLoaded = false"></script>')
            cookies = []
        elif page == '/login':
            # Row 2's password probe: a plain sign-in form whose submit navigates, as a real one does.
            body = ('<title>Boaz fixture login</title><form method="post" action="/signed-in">'
                    '<input name="username" autocomplete="username" aria-label="Username" autofocus>'
                    '<input name="password" type="password" autocomplete="current-password" aria-label="Password">'
                    '<button type="submit">Sign in</button></form>')
            cookies = []
        elif page == '/whoami':
            signed_in = f'boaz_session={SESSION}' in self.headers.get('Cookie', '')
            body = f'<title>Boaz fixture {"signed in" if signed_in else "signed out"}</title>'
            cookies = []
        else:
            body = f'<title>Boaz fixture {page}</title><p>{page}</p>'
            cookies = []
        data = body.encode()
        self.send_response(200)
        self.send_header('Content-Type', 'text/html; charset=utf-8')
        self.send_header('Content-Length', str(len(data)))
        self.send_header('Cache-Control', 'no-store')
        for cookie in cookies:
            self.send_header('Set-Cookie', cookie)
        self.end_headers()
        self.wfile.write(data)

    def log_message(self, *args):
        pass


http.server.ThreadingHTTPServer(('127.0.0.1', PORT), Handler).serve_forever()
