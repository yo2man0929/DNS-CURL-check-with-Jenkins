#!/bin/bash

# 更新APT包索引
sudo apt-get update -y

# 安装包以允许APT通过HTTPS使用仓库
sudo apt-get install -y \
    apt-transport-https \
    ca-certificates \
    curl \
    software-properties-common

# 添加清华大学的Docker官方GPG密钥
curl -fsSL https://mirrors.tuna.tsinghua.edu.cn/docker-ce/linux/ubuntu/gpg | sudo apt-key add -

# 向APT源列表中添加清华大学的Docker仓库
sudo add-apt-repository \
   "deb [arch=amd64] https://mirrors.tuna.tsinghua.edu.cn/docker-ce/linux/ubuntu \
   $(lsb_release -cs) \
   stable"

# 更新APT包索引
sudo apt-get update -y

# 安装最新版本的Docker CE
sudo apt-get install -y docker-ce

# 配置Docker镜像加速器（以阿里云为例，确保替换成您的加速器地址）
sudo mkdir -p /etc/docker
sudo tee /etc/docker/daemon.json <<-'EOF'
{
  "registry-mirrors": ["https://0bbqupb9.mirror.aliyuncs.com"]
}
EOF
sudo systemctl daemon-reload
sudo systemctl restart docker

# 添加当前用户到docker组
sudo usermod -aG docker $USER

# 输出Docker版本来验证安装
docker --version

echo "Docker安装成功！"

