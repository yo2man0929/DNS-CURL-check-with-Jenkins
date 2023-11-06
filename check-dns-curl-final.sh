#!/bin/sh
set -x 


LOCAL_URL_FILE="./urls.txt"
JENKINS_URL_FILE="/var/jenkins_home/urls.txt" # 記得把urls.txt放到/var/jenkins_home/底下，也就是 data/jenkins_configuration/底下
SLACK_WEBHOOK_URL=`cat /var/jenkins_home/slack.key` # local test

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
  if [ ! -f "$JENKINS_URL_FILE" ]; then
  echo "1919.com" > /var/jenkins_home/urls.txt
  fi
fi


check_command() {
  if ! command -v "$1" > /dev/null 2>&1; then
    apt-get install "$1" -y
  fi
}


post_to_slack() {
  curl -X POST -H 'Content-type: application/json' --data "$1" "$SLACK_WEBHOOK_URL"
}


check_http_service() {
  local url=$1
  local status_code
  local effective_url

  status_code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 5 "$url")
  effective_url=$(curl -Ls -o /dev/null -w '%{url_effective}' --max-time 5 "$url")
  js_redirect=$(curl -s --max-time 5 "$url" | grep -Eo 'window.location.href\s*=\s*"[^"]+"')
  # curl的結果會多http，需要過濾掉
  url_without_scheme=$(echo $effective_url | sed -E 's,https?://,,; s,/.*,,g')
	
  if [ -n "$js_redirect" ]; then
      js_redirect_url=$(echo $js_redirect | sed -E 's/window.location.href\s*=\s*"([^"]+)".*/\1/')
      # 移除js url的http
      js_redirect_url_without_scheme=$(echo $js_redirect_url | sed -E 's,https?://,,; s,/.*,,g')
      echo "${status_code}|REDIRECT|${js_redirect_url_without_scheme}"
  elif [ "$url" != "$url_without_scheme" ]; then
    echo "${status_code}|REDIRECT|${url_without_scheme}"
  else
    echo "${status_code}|NO_REDIRECT|$url"
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
  
  # 先濾掉換行符號
  formatted_message=$(echo "$message" | tr '\n' ' ')
  local json_body=$(jq -n --arg title "$title" --arg msg "$formatted_message" '{title: $title, msg: $msg}')

  curl -X POST 'http://alert-server.hinno.site/normal/DevOps_cronjob' \
    -H 'accept: application/json' \
    -H 'Content-Type: application/json' \
    -d "$json_body"
}

# 確認curl, dig, awk, sed, jq存在
check_command curl
check_command dig
check_command awk
check_command sed
check_command awk
check_command jq


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

  if [ "$redirect_info" = "REDIRECT" ]; then
    final_url=$(echo "$result" | cut -d'|' -f3)
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
    final_url=$(echo "$http_status_and_url" | cut -d'|' -f3)

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

# 讓 ok, fail 取代 status code
format_results() {
  echo "$1" \
    | sed -E 's/_curl: 3[0-9]{2}/_curl: ok/g' \
    | sed -E 's/_curl: 2[0-9]{2}/_curl: ok/g' \
    | sed -E 's/_curl: 404/_curl: ok/g' \
    | sed -E 's/_curl: 40[0-3]/_curl: fail/g' \
    | sed -E 's/_curl: 5[0-9]{2}/_curl: fail/g' \
    | sed -E 's/_curl: 000/_curl: fail/g' \
    | sed -E 's/redirect_curl: 2[0-9]{2}/redirect_curl: ok/g' \
    | sed -E 's/redirect_curl: 4[0-9]{2}/redirect_curl: ok/g' \
    | sed -E 's/redirect_curl: 5[0-9]{2}/redirect_curl: fail/g' \
    | sed -E 's/redirect_curl: 000/redirect_curl: fail/g' 
}


formatted_results=$(format_results "$results")

if ! echo "$formatted_results" | grep -q "fail"; then
  # No errors found, add the "No Error!無異常" message
  formatted_results="${formatted_results} => No Error!無異常"
  else 
  formatted_results="${formatted_results} => Please check!需要查一下"
fi

# Post results to Slack and the alert server
json_payload=$(printf '{"text":"Results:\n%s"}' "$formatted_results\n==== Domain Checking! ====")

# Uncomment the following line to enable Slack posting
#post_to_slack "$json_payload"

post_to_alert_server "Domain Checking!" "\"${formatted_results}\" ==== Domain Checking! ===="

















