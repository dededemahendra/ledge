#!/usr/bin/env bash
# One-time: create a self-signed code-signing identity so TCC grants survive rebuilds.
set -euo pipefail

IDENTITY="${1:-Ledge Dev}"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

if security find-identity -v -p codesigning | grep -q "$IDENTITY"; then
    echo "Identity '$IDENTITY' already exists — nothing to do."
    exit 0
fi

echo "Minting self-signed code-signing certificate '$IDENTITY'..."
openssl req -x509 -newkey rsa:2048 -sha256 -days 3650 -nodes \
    -keyout "$WORK/key.pem" -out "$WORK/cert.pem" \
    -subj "/CN=$IDENTITY" \
    -addext "basicConstraints=critical,CA:false" \
    -addext "keyUsage=critical,digitalSignature" \
    -addext "extendedKeyUsage=critical,codeSigning" 2>/dev/null

openssl pkcs12 -export -out "$WORK/identity.p12" \
    -inkey "$WORK/key.pem" -in "$WORK/cert.pem" \
    -passout pass: -name "$IDENTITY"

echo "Importing into the login keychain."
echo "macOS may ask you to allow keychain access — click Allow."
security import "$WORK/identity.p12" \
    -k "$HOME/Library/Keychains/login.keychain-db" \
    -P "" -T /usr/bin/codesign -A

echo
echo "Result:"
security find-identity -v -p codesigning | grep "$IDENTITY" \
    || { echo "FAILED: identity not found after import." >&2
         echo "Fallback: Keychain Access → Certificate Assistant →" >&2
         echo "  Create a Certificate: name '$IDENTITY', type 'Code Signing', self-signed." >&2
         exit 1; }
echo "Done. 'make dev' will now sign with '$IDENTITY'."
