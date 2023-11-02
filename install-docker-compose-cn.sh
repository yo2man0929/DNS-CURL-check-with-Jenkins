#!/bin/bash

# 更新軟件包列表
sudo apt-get update -y

# 安裝Python開發包和構建工具
sudo apt-get install -y python3-pip python3-dev libffi-dev gcc libc-dev make

# 配置pip使用中國科技大學的PyPI鏡像站點
mkdir -p ~/.pip
cat > ~/.pip/pip.conf << EOF
[global]
index-url = https://pypi.mirrors.ustc.edu.cn/simple/
EOF

# 安裝docker-compose
pip3 install docker-compose

# 驗證docker-compose安裝
docker-compose --version

if [ $? -eq 0 ]; then
    echo "Docker Compose 安裝成功！"
else
    echo "Docker Compose 安裝失敗！"
fi

