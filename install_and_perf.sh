#!/bin/bash

# 检查perf是否已安装
if ! command -v perf &> /dev/null; then
    echo "perf工具未安装，更新APT源并安装linux-tools..."

    # 备份原始sources.list
    echo "备份原始sources.list..."
    sudo cp /etc/apt/sources.list /etc/apt/sources.list.bak

    # 替换为阿里云源
    echo "替换为阿里云源..."
    cat <<EOF | sudo tee /etc/apt/sources.list
deb http://mirrors.aliyun.com/debian buster main non-free contrib
deb-src http://mirrors.aliyun.com/debian buster main non-free contrib
deb http://mirrors.aliyun.com/debian buster-updates main non-free contrib
deb-src http://mirrors.aliyun.com/debian buster-updates main non-free contrib
deb http://mirrors.aliyun.com/debian-security buster/updates main non-free contrib
deb-src http://mirrors.aliyun.com/debian-security buster/updates main non-free contrib
EOF

    # 更新APT缓存
    echo "更新APT缓存..."
    sudo apt update -y

    # 获取当前内核版本并安装相应的linux-tools
    kernel_version=$(uname -r | cut -d '.' -f 1,2)
    echo "当前内核版本为: $kernel_version"
    echo "安装linux-tools-$kernel_version..."
    sudo apt install -y linux-tools-$kernel_version
else
    echo "perf工具已安装，跳过更新源和安装步骤。"
fi

# 下载并设置火焰图生成工具
if [ ! -d "FlameGraph" ]; then
    echo "尝试从GitHub下载火焰图生成工具..."
    timeout 5 git clone https://github.com/brendangregg/FlameGraph.git

    if [ $? -eq 124 ]; then
        echo "GitHub下载超时，从本地服务器下载..."
        wget http://192.168.168.199/tool/FlameGraph.zip -O FlameGraph.zip
        if [ -f "FlameGraph.zip" ]; then
            echo "解压FlameGraph.zip..."
            unzip FlameGraph.zip
            chmod 755 ./FlameGraph/*.pl
        else
            echo "下载失败，退出脚本。"
            exit 1
        fi
    else
        echo "GitHub下载成功，设置权限..."
        chmod 755 ./FlameGraph/*.pl
    fi
else
    echo "FlameGraph工具已存在，跳过下载步骤。"
fi

# 设置内核权限
echo "设置内核权限..."
echo 0 | sudo tee /proc/sys/kernel/kptr_restrict

# 运行perf进行性能采样并生成火焰图
echo "运行perf进行性能采样..."
echo "请输入目标进程的PID:"
read pid

perf record -F 99 -p $pid -g -- sleep 60
perf script | ./FlameGraph/stackcollapse-perf.pl | ./FlameGraph/flamegraph.pl > perf.svg

echo "火焰图生成完毕，请将perf.svg文件拖到本地电脑，用浏览器打开查看。"
