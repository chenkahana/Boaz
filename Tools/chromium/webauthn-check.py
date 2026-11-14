#!/usr/bin/env python3
"""Check WebAuthn in a running Boaz through its authenticated loopback automation.

Turn on automation, relaunch Boaz and open any web page. The checks navigate that tab. They use Chromium's DevTools
WebAuthn virtual authenticator, so every request runs through Boaz's real origin, RP ID and secure-context checks
without touching the user's passkeys. Exit status 0 means every check passed. No credential material is printed.
"""
import argparse
import json
import sys
import time

from automation_client import attach, connection, run

API = r"""
(async () => JSON.stringify({
  secureContext: isSecureContext,
  publicKeyCredential: typeof PublicKeyCredential === 'function',
  platformAuthenticator: typeof PublicKeyCredential === 'function'
    ? await PublicKeyCredential.isUserVerifyingPlatformAuthenticatorAvailable() : null,
  conditionalMediation: typeof PublicKeyCredential === 'function' && PublicKeyCredential.isConditionalMediationAvailable
    ? await PublicKeyCredential.isConditionalMediationAvailable() : null,
}))()
"""

# Each scenario resolves to {ok, ...}; `expect` names the DOMException a refusal must raise.
SCENARIOS = r"""
(async () => {
  const rp = location.hostname, report = {};
  const random = n => crypto.getRandomValues(new Uint8Array(n));
  const b64 = buffer => btoa(String.fromCharCode(...new Uint8Array(buffer)));
  const outcome = async (promise, expect) => {
    try { const value = await promise; return expect ? { ok: false, unexpected: 'resolved' } : { ok: true, value }; }
    catch (e) { return expect ? { ok: e.name === expect, error: e.name } : { ok: false, error: e.name + ': ' + e.message }; }
  };
  const creation = (rpID) => ({ publicKey: {
    rp: { id: rpID, name: 'Boaz check' }, challenge: random(32),
    user: { id: random(16), name: 'boaz-check', displayName: 'Boaz check' },
    pubKeyCredParams: [{ type: 'public-key', alg: -7 }, { type: 'public-key', alg: -257 }],
    authenticatorSelection: { residentKey: 'required', userVerification: 'required' },
    timeout: 15000,
  } });
  const request = (rpID, extra = {}) => ({ publicKey: { rpId: rpID, challenge: random(32),
    userVerification: 'required', timeout: 15000, ...extra } });

  const created = await outcome(navigator.credentials.create(creation(rp)));
  report.create = { ok: created.ok, error: created.error };
  if (created.ok) {
    const credential = created.value;
    report.create.type = credential.type;
    report.create.transports = credential.response.getTransports ? credential.response.getTransports() : null;
    const discovered = await outcome(navigator.credentials.get(request(rp)));
    report.getDiscoverable = { ok: discovered.ok && b64(discovered.value.rawId) === b64(credential.rawId)
      && discovered.value.response.userHandle !== null, error: discovered.error };
    const allowed = await outcome(navigator.credentials.get(request(rp,
      { allowCredentials: [{ type: 'public-key', id: credential.rawId }] })));
    report.getAllowList = { ok: allowed.ok && b64(allowed.value.rawId) === b64(credential.rawId), error: allowed.error };
  }
  // A page may only claim its own registrable domain as the RP ID.
  const foreign = rp === 'example.org' ? 'example.net' : 'example.org';
  report.createForeignRP = await outcome(navigator.credentials.create(creation(foreign)), 'SecurityError');
  report.getForeignRP = await outcome(navigator.credentials.get(request(foreign)), 'SecurityError');
  delete report.createForeignRP.value; delete report.getForeignRP.value;
  return JSON.stringify(report);
})()
"""

ABORT = r"""
(async () => {
  const report = {};
  for (const mediation of ['optional', 'conditional']) {
    const controller = new AbortController();
    const pending = navigator.credentials.get({ mediation, signal: controller.signal,
      publicKey: { challenge: crypto.getRandomValues(new Uint8Array(32)), rpId: location.hostname, timeout: 15000 } });
    setTimeout(() => controller.abort(), 500);
    try { await pending; report[mediation] = { ok: false, unexpected: 'resolved' }; }
    catch (e) { report[mediation] = { ok: e.name === 'AbortError', error: e.name }; }
  }
  return JSON.stringify(report);
})()
"""


# webauthn.io's own Register and Authenticate buttons, so the site's real JavaScript (including cancelling its
# passkey-autofill request first) drives the ceremony.
SITE_REGISTER = r"""
(async () => {
  const input = document.getElementById('input-email');
  input.value = 'boaz-check-' + Date.now().toString(36);
  input.dispatchEvent(new Event('input', { bubbles: true }));
  document.getElementById('register-button').click();
  for (let i = 0; i < 40; i++) {
    if (/Success! Now try to authenticate/i.test(document.body.innerText)) return JSON.stringify(true);
    await new Promise(r => setTimeout(r, 250));
  }
  return JSON.stringify(false);
})()
"""
# Signing in navigates to the site's logged-in page, so the click and the check are separate evaluations.
SITE_SIGN_IN = "(async () => { document.getElementById('login-button').click(); return JSON.stringify(true); })()"
SITE_SIGNED_IN = "(async () => JSON.stringify(/You're logged in/i.test(document.body.innerText)))()"


def navigate(ws, url, settle=4):
    ws.call("Page.navigate", url=url)
    time.sleep(settle)


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--records", required=True, help="The profile root's Automation directory")
    parser.add_argument("--page", default="https://example.com/", help="Secure page whose host is the RP ID")
    parser.add_argument("--insecure-page", default="http://neverssl.com/", help="HTTP page that stays HTTP")
    parser.add_argument("--site", action="store_true", help="Also register and sign in on webauthn.io")
    args = parser.parse_args()
    port, token = connection(args.records)
    ws = attach(port, token)
    report = {}

    navigate(ws, args.insecure_page)
    report["insecureContext"] = run(ws, API)
    navigate(ws, args.page)
    report["api"] = run(ws, API)

    ws.call("WebAuthn.enable", enableUI=False)
    authenticator = ws.call("WebAuthn.addVirtualAuthenticator", options={
        "protocol": "ctap2", "ctap2Version": "ctap2_1", "transport": "internal", "hasResidentKey": True,
        "hasUserVerification": True, "isUserVerified": True, "automaticPresenceSimulation": True,
    })["authenticatorId"]
    try:
        report["scenarios"] = run(ws, SCENARIOS)
        stored = ws.call("WebAuthn.getCredentials", authenticatorId=authenticator)["credentials"]
        report["stored"] = {"count": len(stored), "rpIds": sorted({c.get("rpId") for c in stored}),
                            "discoverable": all(c.get("isResidentCredential") for c in stored)}
        # Without presence the request waits, so cancellation is observable.
        ws.call("WebAuthn.setAutomaticPresenceSimulation", authenticatorId=authenticator, enabled=False)
        report["abort"] = run(ws, ABORT)
        ws.call("WebAuthn.setAutomaticPresenceSimulation", authenticatorId=authenticator, enabled=True)
        if args.site:
            navigate(ws, "https://webauthn.io/", settle=5)
            registered = run(ws, SITE_REGISTER)
            run(ws, SITE_SIGN_IN)
            time.sleep(5)
            report["webauthnIO"] = {"registered": registered, "authenticated": run(ws, SITE_SIGNED_IN)}
    finally:
        ws.call("WebAuthn.removeVirtualAuthenticator", authenticatorId=authenticator)
        ws.call("WebAuthn.disable")

    print(json.dumps(report, indent=2))
    scenarios = report["scenarios"]
    required = [
        not report["insecureContext"]["secureContext"] and not report["insecureContext"]["publicKeyCredential"],
        report["api"]["secureContext"] and report["api"]["publicKeyCredential"],
        *(scenarios[name]["ok"] for name in ("create", "getDiscoverable", "getAllowList",
                                             "createForeignRP", "getForeignRP") if name in scenarios),
        "getDiscoverable" in scenarios,
        report["stored"]["count"] == 1 and report["stored"]["discoverable"],
        report["abort"]["optional"]["ok"], report["abort"]["conditional"]["ok"],
        *([report["webauthnIO"]["registered"], report["webauthnIO"]["authenticated"]] if args.site else []),
    ]
    sys.exit(0 if all(required) else 1)


if __name__ == "__main__":
    main()
