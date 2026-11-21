"""Manage the signing certificates CI creates.

Xcode signs archives with a development certificate. A fresh CI runner has
none, so every run creates one through the App Store Connect API, and the
account soon hits Apple's certificate limit. The workflow takes a snapshot
before archiving and revokes whatever new certificate the run created.

Usage (env: ASC_KEY_ID, ASC_ISSUER_ID, ASC_KEY_P8; pip install "pyjwt[crypto]"):
  asc_certs.py list                    list the team's certificates
  asc_certs.py snapshot <file>         save serials of the keychain's signing certificates
  asc_certs.py revoke-new <file>       revoke keychain certificates not in the snapshot
  asc_certs.py signing                 show DAV Drive's App IDs, their capabilities and profiles
  asc_certs.py revoke-ci-made          revoke development certificates created via the API
                                       (by CI runs; never ones made in Xcode or xtool)
"""
import json
import os
import subprocess
import sys
import time
import urllib.parse
import urllib.request

import jwt
from cryptography import x509

API = "https://api.appstoreconnect.apple.com/v1"
DEVELOPMENT_TYPES = {"DEVELOPMENT", "IOS_DEVELOPMENT"}


def token():
    now = int(time.time())
    return jwt.encode(
        {"iss": os.environ["ASC_ISSUER_ID"], "iat": now, "exp": now + 900, "aud": "appstoreconnect-v1"},
        os.environ["ASC_KEY_P8"],
        algorithm="ES256",
        headers={"kid": os.environ["ASC_KEY_ID"], "typ": "JWT"},
    )


def request(method, path, **params):
    url = f"{API}/{path}" + (f"?{urllib.parse.urlencode(params)}" if params else "")
    req = urllib.request.Request(url, method=method, headers={"Authorization": f"Bearer {token()}"})
    with urllib.request.urlopen(req, timeout=30) as response:
        body = response.read()
        return json.loads(body)["data"] if body else None


def certificates():
    return request("GET", "certificates", limit=200,
                   **{"fields[certificates]": "name,displayName,certificateType,platform,expirationDate,serialNumber"})


def norm(serial):
    return serial.upper().lstrip("0")


def keychain_serials():
    """Serials of the code signing certificates in the runner's keychains."""
    pem = subprocess.run(["security", "find-certificate", "-a", "-p"],
                         capture_output=True, text=True).stdout
    serials = set()
    for block in pem.split("-----END CERTIFICATE-----"):
        if "-----BEGIN CERTIFICATE-----" not in block:
            continue
        cert = x509.load_pem_x509_certificate((block.strip() + "\n-----END CERTIFICATE-----\n").encode())
        cn = cert.subject.get_attributes_for_oid(x509.NameOID.COMMON_NAME)
        if cn and cn[0].value.startswith(("Apple Development", "iPhone Developer", "Apple Distribution")):
            serials.add(norm(format(cert.serial_number, "X")))
    return serials


def revoke(cert):
    a = cert["attributes"]
    request("DELETE", f"certificates/{cert['id']}")
    print(f"Revoked {a['certificateType']} '{a['name']}' ({a.get('displayName')}), "
          f"serial {a['serialNumber']}, expiring {a['expirationDate'][:10]}")


def main():
    command = sys.argv[1] if len(sys.argv) > 1 else "list"
    if command == "list":
        for cert in certificates():
            a = cert["attributes"]
            print(f"{a['certificateType']:<22} {a['name']:<40} display={a.get('displayName')!r:<28} "
                  f"expires {a['expirationDate'][:10]}  serial {a['serialNumber']}")
    elif command == "snapshot":
        with open(sys.argv[2], "w") as f:
            f.write("\n".join(sorted(keychain_serials())))
    elif command == "revoke-new":
        with open(sys.argv[2]) as f:
            before = set(f.read().split())
        new = keychain_serials() - before
        if not new:
            print("This run created no certificates.")
        for cert in certificates():
            if norm(cert["attributes"]["serialNumber"]) in new:
                revoke(cert)
    elif command == "signing":
        bundles = request("GET", "bundleIds", limit=200, **{"fields[bundleIds]": "identifier,name,platform"})
        for bundle in bundles:
            ident = bundle["attributes"]["identifier"]
            if not ident.startswith("io.github.crazyquark.davdrive"):
                continue
            print(f"App ID {ident} ({bundle['attributes']['name']})")
            for cap in request("GET", f"bundleIds/{bundle['id']}/bundleIdCapabilities") or []:
                a = cap["attributes"]
                print(f"  capability {a.get('capabilityType')} settings={json.dumps(a.get('settings'))}")
            for prof in request("GET", f"bundleIds/{bundle['id']}/profiles",
                                **{"fields[profiles]": "name,profileType,profileState,createdDate,expirationDate"}) or []:
                a = prof["attributes"]
                print(f"  profile '{a['name']}' {a['profileType']} {a['profileState']} created {a.get('createdDate','')[:16]}")
    elif command == "revoke-ci-made":
        found = False
        for cert in certificates():
            a = cert["attributes"]
            if a["certificateType"] in DEVELOPMENT_TYPES and a.get("displayName") == "Created via API":
                revoke(cert)
                found = True
        if not found:
            print("No development certificates created via the API.")
    else:
        sys.exit(__doc__)


if __name__ == "__main__":
    main()
