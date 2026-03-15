#!/usr/bin/env bash
# Create a self-signed code signing certificate in the login keychain.
# Only needs to run once per Mac. Safe to re-run (checks if cert exists).
set -euo pipefail

CERT_NAME="utv-codesign"

if security find-identity -v -p codesigning | grep -q "$CERT_NAME"; then
    echo "Certificate '$CERT_NAME' already exists."
    security find-identity -v -p codesigning | grep "$CERT_NAME" || true
    exit 0
fi

echo "Creating self-signed code signing certificate '$CERT_NAME'..."

# Create a certificate signing request and self-signed cert via Security framework
cat > /tmp/utv-cert.cfg <<EOF
[ req ]
default_bits       = 2048
distinguished_name = dn
prompt             = no
[ dn ]
CN = $CERT_NAME
[ extensions ]
keyUsage = digitalSignature
extendedKeyUsage = codeSigning
EOF

# Generate key + cert with openssl, then import into keychain
openssl req -x509 -newkey rsa:2048 -nodes \
    -keyout /tmp/utv-cert.key \
    -out /tmp/utv-cert.pem \
    -days 3650 \
    -config /tmp/utv-cert.cfg \
    -extensions extensions \
    -subj "/CN=$CERT_NAME" \
    2>/dev/null

# Bundle into p12 for keychain import (use -legacy for OpenSSL 3.x compat)
openssl pkcs12 -export \
    -out /tmp/utv-cert.p12 \
    -inkey /tmp/utv-cert.key \
    -in /tmp/utv-cert.pem \
    -passout pass:utv \
    -legacy \
    2>/dev/null

# Import into login keychain
security import /tmp/utv-cert.p12 \
    -k ~/Library/Keychains/login.keychain-db \
    -T /usr/bin/codesign \
    -P "utv" \
    -A

# Trust the certificate for code signing
security add-trusted-cert -p codeSign -k ~/Library/Keychains/login.keychain-db /tmp/utv-cert.pem

# Clean up temp files
rm -f /tmp/utv-cert.{cfg,key,pem,p12}

echo ""
echo "Certificate '$CERT_NAME' created and imported into login keychain."
echo ""
echo "On the TARGET Mac (where you'll run the app), you need to trust this cert:"
echo "  1. Export: Keychain Access → login → My Certificates → $CERT_NAME → Export (.cer)"
echo "  2. Import on target: double-click the .cer file"
echo "  3. Trust it: Keychain Access → Get Info → Trust → Code Signing → Always Trust"
echo ""
security find-identity -v -p codesigning | grep "$CERT_NAME" || true
