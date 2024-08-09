#!/bin/bash

# 配置参数
CONFIG_FILE="/userdata/arm-agent/conf/arm-streamConfig2.json"
PROGRAM_NAME="arm-stream"
PROGRAM_ARGS="i 2"
INTERVAL=5  # 监控间隔，单位为秒
MONITOR_DURATION=60  # 每次监控的持续时间，单位为秒
OUTPUT_FILE_PREFIX="system_monitor"
AUDIO_TYPES=("opus" "red" "ISAC" "G722" "ILBC" "PCMU" "PCMA")

monitor_system() {
    local pid_to_monitor=$1
    local output_file=$2

    # 初始化CSV文件
    echo "Timestamp,System CPU Usage (%),System Memory Usage (%),System I/O Read (KB/s),System I/O Write (KB/s),System Network In (KB/s),System Network Out (KB/s),Process CPU Usage (%),Process Memory Usage (%)" > $output_file

    # 获取系统总内存
    TOTAL_MEM=$(grep MemTotal /proc/meminfo | awk '{print $2}')

    # 初始网络流量计数
    NET_IN_PREV=$(cat /proc/net/dev | grep eth0 | awk '{print $2}')
    NET_OUT_PREV=$(cat /proc/net/dev | grep eth0 | awk '{print $10}')

    while true; do
        TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')

        # 系统CPU使用率
        SYS_CPU=$(top -bn1 | grep "Cpu(s)" | sed "s/.*, *\([0-9.]*\)%* id.*/\1/" | awk '{print 100 - $1}')

        # 系统内存使用率
        MEM_FREE=$(grep MemFree /proc/meminfo | awk '{print $2}')
        MEM_USED=$(($TOTAL_MEM - $MEM_FREE))
        MEM_USAGE=$(awk "BEGIN {print $MEM_USED/$TOTAL_MEM*100}")

        # 系统I/O使用情况
        IO_READ=$(iostat -d 1 1 | grep 'sda' | awk 'NR==4 {print $5}')
        IO_WRITE=$(iostat -d 1 1 | grep 'sda' | awk 'NR==4 {print $6}')
        
        # 转换为KB/s
        IO_READ=$(echo "$IO_READ * 1024" | bc)
        IO_WRITE=$(echo "$IO_WRITE * 1024" | bc)

        # 系统网络使用情况
        NET_IN=$(cat /proc/net/dev | grep eth0 | awk '{print $2}')
        NET_OUT=$(cat /proc/net/dev | grep eth0 | awk '{print $10}')
        
        # 计算网络流量差值并转换为KB/s
        NET_IN_DIFF=$(echo "($NET_IN - $NET_IN_PREV) / $INTERVAL / 1024" | bc)
        NET_OUT_DIFF=$(echo "($NET_OUT - $NET_OUT_PREV) / $INTERVAL / 1024" | bc)

        # 更新上一次网络流量计数
        NET_IN_PREV=$NET_IN
        NET_OUT_PREV=$NET_OUT

        # 进程CPU和内存使用情况
        if [ -n $pid_to_monitor ]; then

            USAGE=$(pidstat -urd -h -p 63460 | tail -1 | awk '{print $8,$14}')
            
            # 进程CPU使用率
            PROC_CPU_USAGE=$(echo $USAGE | awk '{print $1}')

            # 进程内存使用率
            PROC_MEM_USAGE=$(echo $USAGE | awk '{print $2}')
        else
            CPU_USAGE="N/A"
            PROC_MEM_USAGE="N/A"
        fi

        # 写入CSV文件
        echo "$TIMESTAMP,$SYS_CPU,$MEM_USAGE,$IO_READ,$IO_WRITE,$NET_IN_DIFF,$NET_OUT_DIFF,$CPU_USAGE,$PROC_MEM_USAGE" >> $output_file

        # 等待下一个监控周期
        sleep $INTERVAL
    done
}

for audio_type in "${AUDIO_TYPES[@]}"; do
    # 修改配置文件
    sed -i "s/\"AudioType\": \".*\"/\"AudioType\": \"$audio_type\"/" $CONFIG_FILE
    echo "Updated AudioType to $audio_type in $CONFIG_FILE."

    # 杀掉程序
    pkill -9 "$PROGRAM_NAME"
    echo "Killed program $PROGRAM_NAME."

    # 查询程序PID
    sleep 8  # 等待程序完全启动

    PID_TO_MONITOR=$(ps aux | grep "$PROGRAM_PATH" | grep "$PROGRAM_ARGS" | grep -v grep | awk '{print $2}' | head -n 1)

    if [ -z "$PID_TO_MONITOR" ]; then
        echo "Error: Unable to find PID for program $PROGRAM_NAME with args $PROGRAM_ARGS"
        exit 1
    else
        echo "Found PID: $PID_TO_MONITOR"
    fi

    # 生成带有AudioType后缀的输出文件名
    OUTPUT_FILE="${OUTPUT_FILE_PREFIX}_${audio_type}.csv"

    # 监控资源使用情况
    monitor_system $PID_TO_MONITOR $OUTPUT_FILE &
    
    # 保存监控进程的PID
    MONITOR_PID=$!

    # 等待一段时间进行监控
    sleep $MONITOR_DURATION  # 监控60秒，可以根据需要调整

    # 停止监控进程
    kill $MONITOR_PID
    echo "Finished monitoring for AudioType $audio_type."
done
