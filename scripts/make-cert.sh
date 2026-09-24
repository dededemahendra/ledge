#!/usr/bin/env bash
# One-time: create a self-signed code-signing identity so TCC grants survive rebuilds.
set -euo pipefail

IDENTITY="${1:-Ledge Dev}"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# A throwaway transport password for the PKCS#12 bundle. It MUST be non-empty:
# `security import` fails an empty-password p12 with "MAC verification failed"
# regardless of which openssl produced it (verified against LibreSSL 3.3.6 and
# OpenSSL 3.6.4, with and without -legacy). The password protects nothing here —
# the file lives in a temp dir for one command — it only has to be non-empty.
P12PASS="ledge-transport"

# NOT `-v`: a self-signed certificate is legitimately untrusted, and
# `find-identity -v` lists only trusted identities, so it reports 0 even after a
# successful import. `codesign` signs happily with an untrusted identity.
if security find-identity -p codesigning | grep -q "$IDENTITY"; then
    echo "Identity '$IDENTITY' already exists — nothing to do."
    exit 0
fi

echo "Minting self-signed code-signing certificate '$IDENTITY'..."
# Pinned to /usr/bin/openssl (Apple's LibreSSL), not the PATH-resolved `openssl`.
# On a machine with Homebrew's OpenSSL 3.x ahead in PATH, its default `pkcs12
# -export` writes PBES2/AES-256/SHA-256 encryption, which `security import`
# cannot parse ("MAC verification failed") regardless of password — it only
# understands the legacy RC2/3DES+SHA-1 PKCS#12 format that LibreSSL still
# writes by default. (OpenSSL 3.x's `-legacy` flag produces that same
# compatible format, but LibreSSL doesn't recognize `-legacy` at all, so
# pinning to the system binary is the one invocation that works either way.)
/usr/bin/openssl req -x509 -newkey rsa:2048 -sha256 -days 3650 -nodes \
    -keyout "$WORK/key.pem" -out "$WORK/cert.pem" \
    -subj "/CN=$IDENTITY" \
    -addext "basicConstraints=critical,CA:false" \
    -addext "keyUsage=critical,digitalSignature" \
    -addext "extendedKeyUsage=critical,codeSigning" 2>/dev/null

/usr/bin/openssl pkcs12 -export -out "$WORK/identity.p12" \
    -inkey "$WORK/key.pem" -in "$WORK/cert.pem" \
    -passout "pass:$P12PASS" -name "$IDENTITY"

echo "Importing into the login keychain."
echo "macOS may ask you to allow keychain access — click Allow."
security import "$WORK/identity.p12" \
    -k "$HOME/Library/Keychains/login.keychain-db" \
    -P "$P12PASS" -T /usr/bin/codesign -A

echo
echo "Result:"
security find-identity -p codesigning | grep "$IDENTITY" \
    || { echo "FAILED: identity not found after import." >&2
         echo "Fallback: Keychain Access → Certificate Assistant →" >&2
         echo "  Create a Certificate: name '$IDENTITY', type 'Code Signing', self-signed." >&2
         exit 1; }
echo "Done. 'make dev' will now sign with '$IDENTITY'."
