#!/bin/bash
# Creates a persistent self-signed code-signing certificate in the login keychain.
#
# WHY: the app reads Claude Code's OAuth token from the keychain. macOS stores a
# keychain "Always Allow" decision as the calling app's *designated requirement*.
# An ad-hoc signature (`codesign --sign -`) has a cdhash-based identity that changes
# on every rebuild, so the stored decision stops matching and macOS re-prompts.
# A signature from a stable certificate has a cert-leaf-based designated requirement
# (`identifier ... and certificate leaf = H"<certhash>"`) that survives every rebuild
# — authorize the keychain once and it sticks.
#
# Idempotent: if the identity already exists, does nothing (regenerating would mint a
# new cert hash and force re-authorization). Run once per machine.

set -e

IDENTITY="Claude Widget Code Signing"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"

if security find-certificate -c "${IDENTITY}" "${KEYCHAIN}" >/dev/null 2>&1; then
  echo "Signing identity '${IDENTITY}' already present — nothing to do."
  exit 0
fi

TMP="$(mktemp -d)"
trap 'rm -rf "${TMP}"' EXIT

openssl genrsa -out "${TMP}/key.pem" 2048 2>/dev/null

cat > "${TMP}/cert.cnf" <<'EOF'
[req]
distinguished_name = dn
x509_extensions    = v3
prompt             = no
[dn]
CN = Claude Widget Code Signing
[v3]
keyUsage           = critical, digitalSignature
extendedKeyUsage   = critical, codeSigning
basicConstraints   = critical, CA:false
EOF

openssl req -x509 -new -key "${TMP}/key.pem" -days 3650 \
  -out "${TMP}/cert.pem" -config "${TMP}/cert.cnf" 2>/dev/null

# Legacy PBE/MAC: macOS `security import` cannot read OpenSSL 3's default AES-256 p12.
openssl pkcs12 -export -inkey "${TMP}/key.pem" -in "${TMP}/cert.pem" \
  -out "${TMP}/identity.p12" -passout pass:cwpass -name "${IDENTITY}" \
  -keypbe PBE-SHA1-3DES -certpbe PBE-SHA1-3DES -macalg sha1 -legacy 2>/dev/null

# -A: let any app (i.e. codesign) use the private key without a per-build prompt.
security import "${TMP}/identity.p12" -k "${KEYCHAIN}" -P "cwpass" -T /usr/bin/codesign -A

echo "Created signing identity '${IDENTITY}'."
echo "Now rebuild (./build.sh) and click 'Always Allow' once at the keychain prompt."
