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

# Build, sign with your local identity, and (re)install to /Applications.
#
# With the identity from ./scripts/make-local-signing-cert.sh, permissions and
# settings survive every rebuild. Without it, the build is ad-hoc signed and
# macOS will ask for Accessibility again after each install.
set -euo pipefail
cd "$(dirname "$0")/.."

NAME="${JOT_SIGNING_IDENTITY:-Jot Local Signing}"
APP="build/Build/Products/Debug/Jot.app"

./scripts/build.sh -derivedDataPath build

if security find-certificate -c "$NAME" >/dev/null 2>&1; then
  # --deep: debug builds carry Jot.debug.dylib next to the stub executable.
  codesign --force --deep --sign "$NAME" --entitlements App/Jot.entitlements --timestamp=none "$APP"
  echo "Signed with \"$NAME\" — permissions will carry over."
else
  echo "warning: no \"$NAME\" identity — keeping the ad-hoc signature." >&2
  echo "         Run ./scripts/make-local-signing-cert.sh once so permissions survive rebuilds." >&2
fi
codesign --verify --strict "$APP"

# Replace the running copy: quit, swap, relaunch.
if pgrep -x Jot >/dev/null; then
  osascript -e 'tell application id "com.ammaar.jot" to quit' >/dev/null 2>&1 || true
  for _ in {1..20}; do pgrep -x Jot >/dev/null || break; sleep 0.25; done
  pkill -x Jot 2>/dev/null || true
fi
rm -rf /Applications/Jot.app
ditto "$APP" /Applications/Jot.app
open /Applications/Jot.app
echo "Installed /Applications/Jot.app"
