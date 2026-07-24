#!/bin/bash

# Required parameters:
# @raycast.schemaVersion 1
# @raycast.title Chatt
# @raycast.mode silent

# Optional parameters:
# @raycast.icon ./chatgpt.png
# @raycast.packageName ChatGPT
# @raycast.description Opens a temporary ChatGPT conversation with the provided prompt

# Sol parameters:
# command: chatt
# arguments: raw

set -euo pipefail

readonly prompt="${1:-}"
readonly prompt64="$(
  printf '%s' "$prompt" \
    | /usr/bin/base64 \
    | /usr/bin/tr '+/' '-_' \
    | /usr/bin/tr -d '=\r\n'
)"

/usr/bin/open \
  "http://127.0.0.1:17371/launch?prompt64=${prompt64}&temporary=1"
