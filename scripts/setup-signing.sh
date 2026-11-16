#!/usr/bin/env bash
# One-time setup: creates a self-signed code-signing certificate named
# "Keyboard Sounds Local Signing" in your login keychain.
#
# Why: macOS ties the Input Monitoring permission to the app's signature. Ad-hoc
# signatures change on every build, so each rebuild loses the permission. Signing
# with one fixed certificate keeps the permission across rebuilds.
#
# The certificate is only used locally by codesign. It is not trusted system-wide
# and does not change any trust settings. Remove it any time with Keychain Access
# (search for the name above), or:
#   security delete-identity -c "Keyboard Sounds Local Signing"
set -euo pipefail

name="Keyboard Sounds Local Signing"
keychain="$HOME/Library/Keychains/login.keychain-db"

if security find-certificate -c "$name" "$keychain" >/dev/null 2>&1; then
  echo "\"$name\" already exists; nothing to do."
  exit 0
fi

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
pass="$(openssl rand -hex 16)"

cat > "$tmp/cert.cnf" <<EOF
[req]
distinguished_name = dn
x509_extensions = ext
prompt = no
[dn]
CN = $name
[ext]
basicConstraints = critical, CA:false
keyUsage = critical, digitalSignature
extendedKeyUsage = critical, codeSigning
EOF

openssl req -x509 -newkey rsa:2048 -nodes -days 3650 -config "$tmp/cert.cnf" \
  -keyout "$tmp/key.pem" -out "$tmp/cert.pem" 2>/dev/null
openssl pkcs12 -export -inkey "$tmp/key.pem" -in "$tmp/cert.pem" -name "$name" \
  -passout "pass:$pass" -out "$tmp/identity.p12"

# -T lets codesign use the key without a prompt on every build.
security import "$tmp/identity.p12" -k "$keychain" -P "$pass" -T /usr/bin/codesign >/dev/null
echo "Created \"$name\" in your login keychain."
