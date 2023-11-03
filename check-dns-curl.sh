#!/bin/sh
set -x 

LOCAL_URL_FILE="./urls.txt" # 方便local測試
JENKINS_URL_FILE="/var/jenkins_home/urls.txt" # 記得把urls.txt放到Jenkins的volume裡面
SLACK_WEBHOOK_URL="https://hooks.slack.com/services/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"

if [ -z "$1" ] && [ ! -z "$CHECKING_DOMAIN" ]; then
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
  http_status=$(curl -s -o /dev/null -w '%{http_code}' --max-time 2 "$1")
  if [ "$http_status" -ge 200 ] && [ "$http_status" -lt 400 ]; then
    echo "ok"
  else
    echo "fail"
  fi
}

check_dns_resolution() {
  # 提取域名部分，去除URL的路径和潜在的DNS后缀
  local domain=$(echo "$1" | sed -E 's|/.*||' | sed -E 's|_dns$||')

  # 使用dig命令来检查DNS解析
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
check_command curl
check_command dig


if [ ! -f "$URL_FILE" ]; then
  echo "Error: File does not exist: $URL_FILE" >&2
  exit 1
fi

results=""
TIMESTAMP=$(date +%Y%m%d%H%M)
mkdir -p /var/jenkins_home/log/ || true
OUTPUT_FILE="/var/jenkins_home/log/check_results_${TIMESTAMP}"


while IFS= read -r url; do
  http_status=$(check_http_service "$url")
  dns_status=$(check_dns_resolution "$url")
  line="${url}_curl: ${http_status}, ${url}_dns: ${dns_status}"
  results="${results}\\n${line}"
  echo "${line}" >> "${OUTPUT_FILE}.log"
done < "$URL_FILE"

# 檢查額外定義的domain,因為不能用bash的陣列，所以用IFS分割
OLD_IFS="$IFS"
IFS=',' # 设置 IFS 分隔號為逗號
set -f # 禁用路徑名擴展
for domain in $CHECKING_DOMAIN; do
  if [ -n "$domain" ]; then
    http_status=$(check_http_service "$domain")
    dns_status=$(check_dns_resolution "$domain")
    line="${domain}_curl: ${http_status}, ${domain}_dns: ${dns_status}"
    results="${results}\\n${line}"
    echo "${line}" >> "${OUTPUT_FILE}.log"
  fi
done
set +f # 重新啟用路徑名擴展
IFS="$OLD_IFS" # 還原 IFS


json_payload=$(printf '{"text":"Results:\n%s"}' "$results")
#post_to_slack "$json_payload"


post_to_alert_server "TEST: Please ignore it!" "$results"
# End of script

