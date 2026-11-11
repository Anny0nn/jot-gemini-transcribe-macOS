#!/bin/bash
# Copyright 2026 Google LLC
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     https://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

# One-time: create a self-signed code-signing identity in your login keychain so
# local builds keep their macOS permissions across rebuilds.
#
# Why: macOS (TCC and the Keychain) remembers Accessibility, Microphone and the
# API-key keychain grant by the app's code signature. Debug builds are signed
# ad-hoc, and an ad-hoc signature is a hash of that exact build — so every
# rebuild is a "new app" and every permission is asked for again. Signed with a
# stable certificate, every build satisfies the same requirement
# (bundle id + certificate), and the grants stick.
#
# No Apple account involved. The certificate is only trusted for code signing,
# only on this Mac, and only you hold its private key.
set -euo pipefail

NAME="${JOT_SIGNING_IDENTITY:-Jot Local Signing}"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"

if security find-certificate -c "$NAME" "$KEYCHAIN" >/dev/null 2>&1; then
  echo "\"$NAME\" already exists in your login keychain — nothing to do."
  exit 0
fi

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

cat > "$WORK/cert.cnf" <<EOF
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

/usr/bin/openssl req -x509 -newkey rsa:2048 -nodes -days 3650 \
  -keyout "$WORK/key.pem" -out "$WORK/cert.pem" -config "$WORK/cert.cnf" 2>/dev/null
# A throwaway password only protects the file for the import below, then the
# file is deleted. macOS's /usr/bin/openssl (LibreSSL) writes a PKCS#12 the
# Keychain can read.
P12_PASS="$(uuidgen)"
/usr/bin/openssl pkcs12 -export -inkey "$WORK/key.pem" -in "$WORK/cert.pem" \
  -name "$NAME" -out "$WORK/identity.p12" -passout "pass:$P12_PASS"

# -T: let codesign use the private key without a keychain prompt on every build.
security import "$WORK/identity.p12" -k "$KEYCHAIN" -P "$P12_PASS" -T /usr/bin/codesign >/dev/null

echo "Created \"$NAME\" in your login keychain."
echo "macOS may ask for your login password once to trust it for code signing."
# Trust for code signing only (-p codeSign), for this user only.
security add-trusted-cert -p codeSign -k "$KEYCHAIN" "$WORK/cert.pem"
echo "Done. Build and install with ./scripts/install-local.sh"
