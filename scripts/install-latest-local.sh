#!/bin/zsh

set -euo pipefail

readonly REPOSITORY="${SOL_REPOSITORY:-tovam/sol}"
readonly RELEASE_TAG="${SOL_RELEASE_TAG:-sol-development}"
readonly ASSET_NAME="Sol-macOS-unsigned.zip"
readonly CERTIFICATE_NAME="Sol Local Signing"
readonly INSTALL_TARGET="/Applications/Sol.app"
readonly SCRIPT_DIRECTORY="${0:A:h}"
readonly REPOSITORY_ROOT="${SCRIPT_DIRECTORY:h}"
readonly ENTITLEMENTS_PATH="$REPOSITORY_ROOT/macos/sol-macOS/sol-ci.entitlements"

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
  print "Usage: ./scripts/install-latest-local.sh"
  print
  print "Downloads the latest public Sol development build, verifies it,"
  print "signs it with a persistent local certificate, installs it in"
  print "/Applications, and launches it."
  exit 0
fi

if (( $# > 0 )); then
  print -u2 "Unknown argument: $1"
  print -u2 "Run with --help for usage."
  exit 2
fi

require_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    print -u2 "Missing required command: $1"
    exit 1
  fi
}

for command_name in curl shasum ditto codesign security openssl xattr open pgrep pkill sed; do
  require_command "$command_name"
done

if [[ ! -f "$ENTITLEMENTS_PATH" ]]; then
  print -u2 "Missing entitlements file: $ENTITLEMENTS_PATH"
  exit 1
fi

readonly AVAILABLE_KB="$(df -Pk "$REPOSITORY_ROOT" | awk 'NR == 2 { print $4 }')"
if [[ -z "$AVAILABLE_KB" || "$AVAILABLE_KB" -lt 307200 ]]; then
  print -u2 "At least 300 MB of free disk space is required."
  exit 1
fi

readonly WORK_DIRECTORY="$(mktemp -d "${TMPDIR:-/tmp}/sol-local-sign.XXXXXX")"
readonly DOWNLOAD_DIRECTORY="$WORK_DIRECTORY/download"
readonly EXTRACT_DIRECTORY="$WORK_DIRECTORY/extracted"
readonly BACKUP_APP="$WORK_DIRECTORY/previous-Sol.app"
readonly LOGIN_KEYCHAIN="$(security default-keychain -d user | tr -d '"')"

INSTALLATION_IN_PROGRESS=0
HAD_PREVIOUS_APP=0

cleanup() {
  local exit_code=$?
  trap - EXIT INT TERM

  if (( exit_code != 0 && INSTALLATION_IN_PROGRESS == 1 )); then
    print -u2 "Installation failed; restoring the previous app."
    if [[ "$INSTALL_TARGET" == "/Applications/Sol.app" ]]; then
      rm -rf "$INSTALL_TARGET"
    fi
    if (( HAD_PREVIOUS_APP == 1 )) && [[ -d "$BACKUP_APP" ]]; then
      mv "$BACKUP_APP" "$INSTALL_TARGET"
    fi
  fi

  if [[ -n "$WORK_DIRECTORY" && -d "$WORK_DIRECTORY" ]]; then
    rm -rf "$WORK_DIRECTORY"
  fi
  exit "$exit_code"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

find_signing_identity() {
  security find-identity -v -p codesigning "$LOGIN_KEYCHAIN" 2>/dev/null \
    | awk -v name="$CERTIFICATE_NAME" 'index($0, name) > 0 { print $2; exit }'
}

create_signing_identity() {
  local certificate_directory="$WORK_DIRECTORY/certificate"
  local openssl_config="$certificate_directory/openssl.cnf"
  local private_key="$certificate_directory/private-key.pem"
  local traditional_private_key="$certificate_directory/private-key-rsa.pem"
  local certificate="$certificate_directory/certificate.pem"

  mkdir -p "$certificate_directory"

  cat > "$openssl_config" <<'EOF'
[req]
prompt = no
distinguished_name = subject
x509_extensions = extensions

[subject]
CN = Sol Local Signing
O = Sol Local Development

[extensions]
basicConstraints = critical, CA:true
keyUsage = critical, digitalSignature, keyCertSign
extendedKeyUsage = codeSigning
subjectKeyIdentifier = hash
authorityKeyIdentifier = keyid:always
EOF

  print "Creating persistent local signing identity…"
  openssl req \
    -x509 \
    -newkey rsa:3072 \
    -sha256 \
    -days 3650 \
    -nodes \
    -set_serial "0x$(openssl rand -hex 16)" \
    -keyout "$private_key" \
    -out "$certificate" \
    -config "$openssl_config" \
    >/dev/null 2>&1

  # macOS Keychain rejects some PKCS#12 files produced by OpenSSL 3 with
  # errSecDecode (-26276). Importing the traditional RSA key directly avoids
  # that decoder while keeping the private key protected by the login keychain.
  openssl rsa \
    -traditional \
    -in "$private_key" \
    -out "$traditional_private_key" \
    >/dev/null 2>&1

  security import "$traditional_private_key" \
    -k "$LOGIN_KEYCHAIN" \
    -t priv \
    -f openssl \
    -T /usr/bin/codesign \
    >/dev/null

  security add-trusted-cert \
    -r trustRoot \
    -p codeSign \
    -k "$LOGIN_KEYCHAIN" \
    "$certificate"
}

SIGNING_IDENTITY="$(find_signing_identity)"
if [[ -z "$SIGNING_IDENTITY" ]]; then
  create_signing_identity
  SIGNING_IDENTITY="$(find_signing_identity)"
fi

if [[ -z "$SIGNING_IDENTITY" ]]; then
  print -u2 "Could not create a valid '$CERTIFICATE_NAME' identity."
  print -u2 "Open Keychain Access and verify that the certificate is trusted for code signing."
  exit 1
fi

mkdir -p "$DOWNLOAD_DIRECTORY" "$EXTRACT_DIRECTORY"

readonly RELEASE_URL="https://github.com/$REPOSITORY/releases/download/$RELEASE_TAG"
readonly CACHE_BUSTER="$(date +%s)"
readonly ARCHIVE_PATH="$DOWNLOAD_DIRECTORY/$ASSET_NAME"
readonly CHECKSUM_PATH="$DOWNLOAD_DIRECTORY/$ASSET_NAME.sha256"

print "Downloading the latest public build from $REPOSITORY…"
curl \
  --fail \
  --location \
  --retry 3 \
  --connect-timeout 15 \
  -H "Cache-Control: no-cache" \
  "$RELEASE_URL/$ASSET_NAME?local=$CACHE_BUSTER" \
  -o "$ARCHIVE_PATH"
curl \
  --fail \
  --location \
  --retry 3 \
  --connect-timeout 15 \
  -H "Cache-Control: no-cache" \
  "$RELEASE_URL/$ASSET_NAME.sha256?local=$CACHE_BUSTER" \
  -o "$CHECKSUM_PATH"

print "Verifying SHA-256 checksum…"
(
  cd "$DOWNLOAD_DIRECTORY"
  shasum -a 256 -c "$ASSET_NAME.sha256"
)

ditto -x -k "$ARCHIVE_PATH" "$EXTRACT_DIRECTORY"
readonly DOWNLOADED_APP="$EXTRACT_DIRECTORY/Sol.app"
if [[ ! -d "$DOWNLOADED_APP" ]]; then
  print -u2 "The downloaded archive does not contain Sol.app."
  exit 1
fi

print "Signing with '$CERTIFICATE_NAME'…"
codesign \
  --force \
  --deep \
  --sign "$SIGNING_IDENTITY" \
  --options runtime \
  --timestamp=none \
  --entitlements "$ENTITLEMENTS_PATH" \
  "$DOWNLOADED_APP"

codesign --verify --deep --strict --verbose=2 "$DOWNLOADED_APP"
print "Stable designated requirement:"
codesign -d -r- "$DOWNLOADED_APP" 2>&1 | sed -n '1,2p'

if [[ "$INSTALL_TARGET" != "/Applications/Sol.app" ]]; then
  print -u2 "Refusing unexpected install target: $INSTALL_TARGET"
  exit 1
fi

print "Installing in /Applications…"
pkill -x sol >/dev/null 2>&1 || true
trap '' INT TERM
if [[ -d "$INSTALL_TARGET" ]]; then
  mv "$INSTALL_TARGET" "$BACKUP_APP"
  HAD_PREVIOUS_APP=1
fi
INSTALLATION_IN_PROGRESS=1
trap 'exit 130' INT
trap 'exit 143' TERM

ditto "$DOWNLOADED_APP" "$INSTALL_TARGET"
xattr -dr com.apple.quarantine "$INSTALL_TARGET"
codesign --verify --deep --strict "$INSTALL_TARGET"

open "$INSTALL_TARGET"
sleep 5
if ! pgrep -x sol >/dev/null; then
  print -u2 "Sol did not start."
  exit 1
fi

INSTALLATION_IN_PROGRESS=0
print
print "Sol is signed, installed, and running."
print "Signing identity: $CERTIFICATE_NAME"
print "The first signed install requires one final Calendar and Accessibility approval."
print "Future installs made by this script should keep those permissions."
