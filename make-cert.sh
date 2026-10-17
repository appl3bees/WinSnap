#!/bin/zsh
# Creates a self-signed code-signing identity, "WinSnap Local Signing", in your login keychain.
# build.sh signs with it, so macOS keeps the Accessibility permission across rebuilds.
# Only needed if you don't have an Apple Development / Developer ID certificate. Run once.
set -euo pipefail

NAME="WinSnap Local Signing"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"

if security find-identity -v -p codesigning | grep -q "\"$NAME\""; then
    echo "\"$NAME\" already exists; nothing to do."
    exit 0
fi

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
cat > "$TMP/cert.cnf" <<EOF
[req]
distinguished_name = dn
x509_extensions = ext
prompt = no
[dn]
CN = $NAME
[ext]
basicConstraints = critical, CA:false
keyUsage = critical, digitalSignature
extendedKeyUsage = critical, codeSigning
EOF

# /usr/bin/openssl is LibreSSL; a Homebrew OpenSSL 3 .p12 fails to import. Ten years, so it doesn't expire out from under the permission.
/usr/bin/openssl req -x509 -newkey rsa:2048 -nodes -days 3650 -config "$TMP/cert.cnf" \
    -keyout "$TMP/key.pem" -out "$TMP/cert.pem" 2>/dev/null
# security(1) won't import a passwordless .p12, so use a throwaway password.
/usr/bin/openssl pkcs12 -export -inkey "$TMP/key.pem" -in "$TMP/cert.pem" -name "$NAME" \
    -out "$TMP/id.p12" -passout pass:winsnap
security import "$TMP/id.p12" -k "$KEYCHAIN" -P winsnap -T /usr/bin/codesign

echo "Trusting the certificate for code signing (macOS will ask for your password)..."
security add-trusted-cert -r trustRoot -p codeSign -k "$KEYCHAIN" "$TMP/cert.pem"

security find-identity -v -p codesigning | grep "\"$NAME\""
echo "Done. Run ./build.sh to sign with it."
