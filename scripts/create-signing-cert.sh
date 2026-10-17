#!/bin/zsh
# Creates a self-signed code signing identity in your login keychain, once.
# build.sh signs with it so every build has the same designated requirement and macOS keeps
# WinSnap's Accessibility permission across rebuilds (ad-hoc signatures change on every build).
set -euo pipefail

NAME="${WINSNAP_SIGN_IDENTITY:-WinSnap Self-Signed}"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"

if security find-identity -p codesigning | grep -qF "\"$NAME\""; then
    echo "\"$NAME\" already exists; nothing to do."
    exit 0
fi

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

cat > "$TMP/cert.cnf" <<CNF
[req]
distinguished_name = dn
prompt = no
x509_extensions = ext
[dn]
CN = $NAME
[ext]
basicConstraints = critical,CA:false
keyUsage = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
CNF

# The system LibreSSL writes a PKCS#12 that `security import` accepts; Homebrew's OpenSSL 3 doesn't by default.
/usr/bin/openssl req -x509 -newkey rsa:2048 -nodes -days 3650 -config "$TMP/cert.cnf" \
    -keyout "$TMP/key.pem" -out "$TMP/cert.pem" 2>/dev/null
/usr/bin/openssl pkcs12 -export -inkey "$TMP/key.pem" -in "$TMP/cert.pem" -name "$NAME" \
    -out "$TMP/id.p12" -passout pass:winsnap
security import "$TMP/id.p12" -k "$KEYCHAIN" -P winsnap -T /usr/bin/codesign

echo "Created \"$NAME\". Rebuild with ./build.sh --install."
echo "macOS lists it as untrusted; that's fine for signing your own builds."
