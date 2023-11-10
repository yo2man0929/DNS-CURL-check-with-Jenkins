# /usr/bin/env bash

FLYVPN_REGION_LIST=${FLYVPN_REGION_LIST} # 
#FLYVPN_REGION_LIST="Singapore #37,Kuala Lumpur #17" # local test
# install tar


if [ ! -f "/usr/bin/flyvpn" ] ; then
    echo " ## [INFO] Install FlyVPN ## "
    if curl -o /root/flyvpn-x86_64-6.2.2.0.tar.gz https://www.flyvpn.com/files/downloads/linux/flyvpn-x86-6.2.2.0.tar.gz; then
        echo "Extracting the downloaded file:"
        tar -xvf /root/flyvpn-x86_64-6.2.2.0.tar.gz -C /usr/bin
    else
        echo "Failed to download FlyVPN."
        exit 1
    fi
fi

# Check and add i386 architecture if not present
if ! dpkg --print-foreign-architectures | grep -q 'i386'; then
    dpkg --add-architecture i386
    apt-get update
fi

# Check and install necessary i386 packages
for package in libc6:i386 libncurses5:i386 libstdc++6:i386; do
    if ! dpkg -l | grep -q "$package"; then
        apt-get install -y "$package"
    fi
done

flyvpn_conf_check() {
    cat << EOF > /etc/flyvpn.conf
user inno1558@gmail.com
pass vpn8290
protocol proxy
EOF
}

run_test() {
    echo "===========test=============="
    hostname
    echo "===========test=============="
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
            run_test
            flyvpn_disconnect
        done
        set +f
        IFS="$OLD_IFS"
    else
        echo " ## [INFO] Use Hanoi for Default region ## "
        Hanoi=$(flyvpn list | grep ok | cut -f3- -d' ' | awk '{$1=$1;print}' | grep -i hanoi | head -1)
        if [ -n "$Hanoi" ]; then
            flyvpn_connect "$Hanoi"
            run_test
            flyvpn_disconnect
        else
            echo "Error: Could not find Hanoi region."
            exit 1
        fi
    fi
}

flyvpn_conf_check
flyvpn_region_select