#!/bin/sh

URL_FILE="urls.txt"
SLACK_WEBHOOK_URL="https://hooks.slack.com/services/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"

check_command() {
  if ! command -v "$1" > /dev/null 2>&1; then
    echo "Error: $1 is required but not installed." >&2
    exit 1
  fi
}

post_to_slack() {
  curl -X POST -H 'Content-type: application/json' --data "$1" "$SLACK_WEBHOOK_URL"
}

check_http_service() {
  http_status=$(curl -s -o /dev/null -w '%{http_code}' "$1")
  if [ "$http_status" -ge 200 ] && [ "$http_status" -lt 400 ]; then
    echo "ok"
  else
    echo "fail"
  fi
}

check_dns_resolution() {
  if dig "$1" +short > /dev/null; then
    echo "ok"
  else
    echo "fail"
  fi
}

# Check if required commands are available
check_command curl
check_command dig

# Ensure the URL file exists
if [ ! -f "$URL_FILE" ]; then
  echo "Error: File does not exist: $URL_FILE" >&2
  exit 1
fi

# Prepare the results variable and timestamp
results=""
TIMESTAMP=$(date +%Y%m%d%H%M)
OUTPUT_FILE="/tmp/check_results_${TIMESTAMP}"

# Read URLs from the file and check them
while IFS= read -r url; do
  http_status=$(check_http_service "$url")
  dns_status=$(check_dns_resolution "$url")
  line="${url}_curl: ${http_status}, ${url}_dns: ${dns_status}"
  results="${results}\\n${line}"
  echo "${line}" >> "${OUTPUT_FILE}.log"
done < "$URL_FILE"

# Read additional domains provided as command-line arguments separated by commas
echo "$1" | tr ',' '\n' | while read domain; do
  if [ -n "$domain" ]; then
    http_status=$(check_http_service "$domain")
    dns_status=$(check_dns_resolution "$domain")
    line="${domain}_curl: ${http_status}, ${domain}_dns: ${dns_status}"
    results="${results}\\n${line}"
    echo "${line}" >> "${OUTPUT_FILE}.log"
  fi
done

# Format the results as a JSON object and post to Slack
json_payload=$(printf '{"text":"Results:\n%s"}' "$results")
post_to_slack "$json_payload"

# End of script

