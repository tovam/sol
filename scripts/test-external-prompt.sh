#!/bin/zsh

set -euo pipefail

readonly SOL_CONFIG_PATH="${SOL_CONFIG_PATH:-${HOME}/.sol.yml}"

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
	print "Usage: ./scripts/test-external-prompt.sh"
	print
	print "Opens a one-shot Sol prompt and waits for its JSON response."
	print "The endpoint and token are read from ~/.sol.yml by default."
	print "They can be overridden with SOL_ENDPOINT and SOL_TOKEN."
	exit 0
fi

if (( $# > 0 )); then
	print -u2 "Unknown argument: $1"
	print -u2 "Run with --help for usage."
	exit 2
fi

for required_command in awk curl; do
	if ! command -v "$required_command" >/dev/null 2>&1; then
		print -u2 "Missing required command: $required_command"
		exit 1
	fi
done

read_api_value() {
	local requested_key="$1"
	awk -v requested_key="$requested_key" '
		function trim(value) {
			gsub(/^[[:space:]]+|[[:space:]]+$/, "", value)
			return value
		}

		{
			raw_line = $0
			if (raw_line ~ /^[^[:space:]]/) {
				header = raw_line
				sub(/[[:space:]]*#.*/, "", header)
				in_api = trim(header) == "api:"
				next
			}

			if (!in_api) next
			line = trim(raw_line)
			if (line == "" || substr(line, 1, 1) == "#") next

			separator = index(line, ":")
			if (separator == 0) next
			key = trim(substr(line, 1, separator - 1))
			if (key != requested_key) next

			value = trim(substr(line, separator + 1))
			quote = substr(value, 1, 1)
			if (quote == "\"" || quote == "\047") {
				value = substr(value, 2)
				closing_quote = index(value, quote)
				if (closing_quote > 0) value = substr(value, 1, closing_quote - 1)
			} else {
				sub(/[[:space:]]+#.*$/, "", value)
				value = trim(value)
			}

			print value
			exit
		}
	' "$SOL_CONFIG_PATH"
}

if [[ ! -f "$SOL_CONFIG_PATH" && ( -z "${SOL_ENDPOINT:-}" || -z "${SOL_TOKEN:-}" ) ]]; then
	print -u2 "Missing Sol configuration: $SOL_CONFIG_PATH"
	print -u2 "Launch Sol once, or set SOL_ENDPOINT and SOL_TOKEN."
	exit 1
fi

config_endpoint=""
config_token=""
config_enabled="true"
if [[ -f "$SOL_CONFIG_PATH" ]]; then
	config_endpoint="$(read_api_value endpoint)"
	config_token="$(read_api_value token)"
	config_enabled="$(read_api_value enabled)"
	config_enabled="${config_enabled:-true}"
fi

sol_endpoint="${SOL_ENDPOINT:-$config_endpoint}"
sol_token="${SOL_TOKEN:-$config_token}"
api_enabled="${SOL_API_ENABLED:-$config_enabled}"

if [[ "$api_enabled" == "false" ]]; then
	print -u2 "The Sol API is disabled in $SOL_CONFIG_PATH"
	exit 1
fi

if [[ -z "$sol_endpoint" || -z "$sol_token" ]]; then
	print -u2 "Could not read api.endpoint and api.token from $SOL_CONFIG_PATH"
	exit 1
fi

readonly prompt_url="${sol_endpoint%/}/v1/ui/prompts"

print "Opening a Sol one-shot prompt…"
print "The HTTP request will finish when you choose a row, submit text, cancel, or wait 2 minutes."
print

# Supplying the Authorization header through a file descriptor keeps the token
# out of curl's command-line arguments while the long-lived request is pending.
curl \
	--config <(print -r -- "header = \"Authorization: Bearer ${sol_token}\"") \
	--fail-with-body \
	--silent \
	--show-error \
	--request POST \
	--header "Content-Type: application/json" \
	--data-binary @- \
	"$prompt_url" <<JSON
{
  "source": {
    "name": "Shell test",
    "pid": $$
  },
  "title": "Dans quel pays habites-tu ?",
  "message": "Choisis une proposition ou écris une autre réponse.",
  "kind": "choice-or-input",
  "items": [
    {
      "id": "france",
      "label": "France",
      "detail": "Europe occidentale",
      "icon": { "type": "emoji", "value": "🇫🇷" },
      "value": { "countryCode": "FR" }
    },
    {
      "id": "spain",
      "label": "Espagne",
      "detail": "Péninsule Ibérique",
      "icon": { "type": "emoji", "value": "🇪🇸" },
      "value": { "countryCode": "ES" }
    },
    {
      "id": "italy",
      "label": "Italie",
      "detail": "Europe méridionale",
      "icon": { "type": "emoji", "value": "🇮🇹" },
      "value": { "countryCode": "IT" }
    },
    {
      "id": "montenegro",
      "label": "Monténégro",
      "detail": "Balkans",
      "icon": { "type": "emoji", "value": "🇲🇪" },
      "value": { "countryCode": "ME" }
    }
  ],
  "input": {
    "placeholder": "Autre pays…",
    "initialValue": "",
    "secure": false,
    "minLength": 2,
    "maxLength": 80
  },
  "dismiss": {
    "escape": true,
    "outsideClick": false
  },
  "sensitive": false,
  "timeoutMs": 120000
}
JSON

print
