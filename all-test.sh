#!/bin/sh
set -x

# Variables from the first script
LOCAL_URL_FILE="./urls.txt"
JENKINS_URL_FILE="/var/jenkins_home/urls.txt"
SLACK_WEBHOOK_URL=$(cat /var/jenkins_home/slack.key)
CHECKING_DOMAIN=${CHECKING_DOMAIN:-$1}
LOG_DIR="/var/jenkins_home/log/"
TIMESTAMP=$(date +%Y%m%d%H%M)
OUTPUT_FILE="${LOG_DIR}check_results_${TIMESTAMP}.log"
PROXY="socks5://127.0.0.1:1080" # local test

# Functions from the first script
initialize_environment() {
  mkdir -p "$LOG_DIR"
  if [ ! -f "$JENKINS_URL_FILE" ]; then
    echo "1919.com" > "$JENKINS_URL_FILE"
  fi
  if [ -f "$LOCAL_URL_FILE" ]; then
    URL_FILE="$LOCAL_URL_FILE"
  else
    URL_FILE="$JENKINS_URL_FILE"
  fi
}

check_required_commands() {
  for cmd in curl dig awk sed jq tar; do
    if ! command -v "$cmd" > /dev/null 2>&1; then
      apt-get install "$cmd" -y
    fi
  done
}

trace_domains() {
  # Reset the results variable
  results=""

  # Check domains from urls.txt
  while IFS= read -r url; do
    process_url "$url"
  done < "$URL_FILE"

  # Check additional domains set in CHECKING_DOMAIN, if provided
  OLD_IFS="$IFS"
  IFS=','
  set -f
  for domain in $CHECKING_DOMAIN; do
    if [ -n "$domain" ]; then
      process_url "$domain"
    fi
  done
  set +f
  IFS="$OLD_IFS"
}

process_url() {
  local url=$1
  local result=$(check_single_url "$url")
  local http_status=$(echo "$result" | cut -d'|' -f1)
  local redirect_info=$(echo "$result" | cut -d'|' -f2)
  local dns_status=$(check_dns_resolution "$url")
  local line="${url}_curl: ${http_status}, ${url}_dns: ${dns_status}"
  if [ -n "$PROXY" ]; then
    curl_cmd="$curl_cmd --proxy $PROXY"
  fi
  if [ "$redirect_info" = "REDIRECT" ]; then
    local final_url=$(echo "$result" | cut -d'|' -f3)
    if [ -n "$final_url" ]; then
      local redirect_http_status=$(curl -s -o /dev/null -w '%{http_code}' --max-time 2 "$final_url")
      local dns_redirect_status=$(check_dns_resolution "$final_url")
      line="${line}, redirect_to: ${final_url}, redirect_curl: ${redirect_http_status}, redirect_dns: ${dns_redirect_status}"
    fi
  fi

  # Append the result to the cumulative results variable
  results="${results}\n${line}"
  echo "$line" >> "$OUTPUT_FILE"
}

check_single_url() {
  local url=$1
  local curl_cmd="curl -s -o /dev/null -w '%{http_code}' --max-time 5"
  if [ -n "$PROXY" ]; then
    curl_cmd="$curl_cmd --proxy $PROXY"
  fi
  local status_code=$($curl_cmd "$url")
  local effective_url=$(curl -Ls -o /dev/null -w '%{url_effective}' --max-time 5 "$url")
  local js_redirect=$(curl -s --max-time 5 "$url" | grep -Eo 'window.location.href\s*=\s*"[^"]+"')
  local url_without_scheme=$(echo $effective_url | sed -E 's,https?://,,; s,/.*,,g')
  if [ -n "$js_redirect" ]; then
    local js_redirect_url=$(echo $js_redirect | sed -E 's/window.location.href\s*=\s*"([^"]+)".*/\1/')
    local js_redirect_url_without_scheme=$(echo $js_redirect_url | sed -E 's,https?://,,; s,/.*,,g')
    echo "${status_code}|REDIRECT|${js_redirect_url_without_scheme}"
  elif [ "$url" != "$url_without_scheme" ]; then
    echo "${status_code}|REDIRECT|${url_without_scheme}"
  else
    echo "${status_code}|NO_REDIRECT|$url"
  fi
}

check_dns_resolution() {
  local domain=$1
  if dig +time=2 +retry=0 "$domain" +short A | grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$' > /dev/null; then
    echo "ok"
  else
    echo "fail"
  fi
}

format_results() {
  local results=$1
  local formatted_results=$(echo "$results" \
    | sed -E "s/_curl: '3[0-9]{2}'/_curl: ok/g" \
    | sed -E "s/_curl: '2[0-9]{2}'/_curl: ok/g" \
    | sed -E "s/_curl: '404'/_curl: ok/g" \
    | sed -E "s/_curl: '40[0-3]'/_curl: fail/g" \
    | sed -E "s/_curl: '5[0-9]{2}'/_curl: fail/g" \
    | sed -E "s/_curl: '000'/_curl: fail/g" \
    | sed -E "s/redirect_curl: 2[0-9]{2}/redirect_curl: ok/g" \
    | sed -E "s/redirect_curl: 4[0-9]{2}/redirect_curl: ok/g" \
    | sed -E "s/redirect_curl: 5[0-9]{2}/redirect_curl: fail/g" \
    | sed -E "s/redirect_curl: 3[0-9]{2}/redirect_curl: ok/g" \
    | sed -E "s/redirect_curl: 000/redirect_curl: fail/g")

  if ! echo "$formatted_results" | grep -q "fail"; then
    formatted_results="${formatted_results} => No Error!無異常"
  else 
    formatted_results="${formatted_results} => Please check!需要查一下"
  fi

  echo "$formatted_results"
}


post_results() {
  local formatted_results=$1
  local json_payload=$(printf '{"text":"Results:\n%s"}' "$formatted_results\n==== Domain Checking! ====")
  post_to_slack "$json_payload"
  #post_to_alert_server "Domain Checking!" "\"${formatted_results}\" ==== Domain Checking! ===="
}

post_to_slack() {
  local payload=$1
  curl -X POST -H 'Content-type: application/json' --data "$payload" "$SLACK_WEBHOOK_URL"
}

post_to_alert_server() {
  local title=$1
  local message=$2
  local json_body=$(jq -n --arg title "$title" --arg msg "$message" '{title: $title, msg: $msg}')
  curl -X POST 'http://alert-server.hinno.site/normal/DevOps_cronjob' \
    -H 'accept: application/json' \
    -H 'Content-Type: application/json' \
    -d "$json_body"
}

# Functions from the second script
flyvpn_conf_check() {
  cat << EOF > /etc/flyvpn.conf
user inno1558@gmail.com
pass vpn8290
protocol proxy
EOF
}

flyvpn_connect() {
  echo " ## [INFO] FlyVPN connect in background ## "
  flyvpn login &> /tmp/flyvpn.log &
  nohup flyvpn connect "$1" &> /tmp/flyvpn.log &
  sleep 3 && cat /tmp/flyvpn.log | tail -n 10
}

flyvpn_disconnect() {
  flyvpn_pid=$(ps aux | grep '[f]lyvpn' | awk '{print $2}')
  if [ -n "$flyvpn_pid" ]; then
    for pid in $flyvpn_pid; do
      kill -9 "$pid" 2>/dev/null
      echo "Killed FlyVPN process $pid"
    done
  fi
  echo " ## [INFO] FlyVPN disconnect ## "
}

flyvpn_region_select() {
  if [ -n "$FLYVPN_REGION_LIST" ]; then
    OLD_IFS="$IFS"
    IFS=','
    set -f
    for region_vpn in $FLYVPN_REGION_LIST; do 
      echo " ## [INFO] Use $region_vpn ## "
      flyvpn_connect "$region_vpn"
      trace_domains
      formatted_results=$(format_results "$results")
      post_results "$formatted_results"
      flyvpn_disconnect
    done
    set +f
    IFS="$OLD_IFS"
  else
    echo " ## [INFO] Use Hanoi for Default region ## "
    Hanoi=$(flyvpn list | grep ok | cut -f3- -d' ' | awk '{$1=$1;print}' | grep -i hanoi | head -1)
    if [ -n "$Hanoi" ]; then
      flyvpn_connect "$Hanoi"
      trace_domains
      formatted_results=$(format_results "$results")
      post_results "$formatted_results"
      flyvpn_disconnect
    else
      echo "Error: Could not find Hanoi region."
      exit 1
    fi
  fi
}

# Main execution

initialize_environment
check_required_commands
flyvpn_conf_check
flyvpn_region_select

