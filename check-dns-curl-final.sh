#!/bin/sh
set -x 


LOCAL_URL_FILE="./urls.txt"
JENKINS_URL_FILE="/var/jenkins_home/urls.txt" # 記得把urls.txt放到/var/jenkins_home/底下
SLACK_WEBHOOK_URL="https://hooks.slack.com/services/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"

# 方便測試，可以直接在這裡設定要測試的domain
if [ -z "$1" ] && [ ! -z "$CHECKING_DOMAIN" ]; then
  #讓jenkins可以設定要測試的domain
  CHECKING_DOMAIN=$CHECKING_DOMAIN
elif [ ! -z "$1" ]; then
  CHECKING_DOMAIN=$1
fi

if [ -f "$LOCAL_URL_FILE" ]; then
  URL_FILE="$LOCAL_URL_FILE"
else
  URL_FILE="$JENKINS_URL_FILE"
fi


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
  local url=$1
  local status_code
  local redirect_url

  status_code=$(curl -Ls -o /dev/null -w '%{http_code}' --max-time 5 "$url")
  redirect_url=$(curl -Ls -o /dev/null -w '%{url_effective}' --max-time 5 "$url")

  if [ "$status_code" -ge 300 ] && [ "$status_code" -lt 400 ]; then
    echo "${status_code}|REDIRECT"
  else
    echo "${status_code}|${redirect_url}"
  fi
}

check_dns_resolution() {
  domain=$(echo "$1" | sed -E 's|http(s)?://||' | sed -E 's|(/.*)?$||' | sed -E 's|_dns$||')
  if dig +time=2 +retry=0 "$domain" +short A | grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$' > /dev/null; then
    echo "ok"
  else
    echo "fail"
  fi
}


post_to_alert_server() {
  local title="$1"
  local message="$2"
  curl -X 'POST' \
    'http://alert-server.hinno.site/normal/DevOps_cronjob' \
    -H 'accept: application/json' \
    -H 'Content-Type: application/json' \
    -d "{
          \"title\": \"$title\",
          \"msg\": \"$message\"
        }"
}

# 確認curl, dig, awk, sed存在
check_command curl
check_command dig
check_command awk
check_command sed

# 確認urls.txt存在
if [ ! -f "$URL_FILE" ]; then
  echo "Error: File does not exist: $URL_FILE" >&2
  exit 1
fi

# 初始化變數
results=""
TIMESTAMP=$(date +%Y%m%d%H%M)
LOG_DIR="/var/jenkins_home/log/"
OUTPUT_FILE="${LOG_DIR}check_results_${TIMESTAMP}.log"

mkdir -p "$LOG_DIR" || true

# 檢查urls.txt裡面的domain
while IFS= read -r url; do
  result=$(check_http_service "$url")
  http_status=$(echo "$result" | cut -d'|' -f1)
  redirect_info=$(echo "$result" | cut -d'|' -f2)

  dns_status=$(check_dns_resolution "$url")
  line="${url}_curl: ${http_status}, ${url}_dns: ${dns_status}"

  # If there was a redirect, then the URL has changed
  if [ "$redirect_info" = "REDIRECT" ]; then
    # Since it's a redirect, we need to extract the redirect URL using the Location header
    final_url=$(curl -Ls -I "$url" | grep -i "^Location:" | tail -n1 | sed 's/Location: //')
    if [ -n "$final_url" ]; then
      redirect_http_status=$(curl -s -o /dev/null -w '%{http_code}' --max-time 2 "$final_url")
      dns_redirect_status=$(check_dns_resolution "$final_url")
      line="${line}, redirect_to: ${final_url}, redirect_curl: ${redirect_http_status}, redirect_dns: ${dns_redirect_status}"
    fi
  fi

  results="${results}\\n${line}"
  echo "$line" >> "$OUTPUT_FILE"
done < "$URL_FILE"


# 檢查jenkins設定的domain（不在urls.txt)，因為不用bash，所以IFS要設定，比較複雜
OLD_IFS="$IFS"
IFS=','
set -f
for domain in $CHECKING_DOMAIN; do
  if [ -n "$domain" ]; then
    # Get HTTP status and final URL after redirects
    http_status_and_url=$(check_http_service "$domain")
    http_status=$(echo "$http_status_and_url" | cut -d'|' -f1)
    final_url=$(echo "$http_status_and_url" | cut -d'|' -f2)

    dns_status=$(check_dns_resolution "$domain")
    redirect_dns_status="not_applicable"
    redirect_curl_status="not_applicable"

    line="${domain}_curl: ${http_status}, ${domain}_dns: ${dns_status}"
    # 假如有redirect，就要再檢查一次
    if [ "$final_url" != "$domain" ]; then
      redirect_dns_status=$(check_dns_resolution "$final_url")
      redirect_curl_status=$(curl -s -o /dev/null -w '%{http_code}' --max-time 5 "$final_url")
      line="${line}, redirect_to: ${final_url}, redirect_curl: ${redirect_curl_status}, redirect_dns: ${redirect_dns_status}"
    fi

    results="${results}\\n${line}"
    echo "$line" >> "$OUTPUT_FILE"
  fi
done
set +f
IFS="$OLD_IFS"


# Post results to Slack and the alert server
#json_payload=$(printf '{"text":"Results:\n%s"}' "$results")
# Uncomment the following line to enable Slack posting
#post_to_slack "$json_payload"

post_to_alert_server "TEST: Please ignore it!" "$results"

# End of script
