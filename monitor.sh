#!/bin/bash

# 配置参数
CONFIG_FILE="/userdata/arm-agent/conf/arm-streamConfig2.json"
PROGRAM_NAME="arm-stream"
PROGRAM_ARGS="i 2"
INTERVAL=2  # 监控间隔，单位为秒
MONITOR_DURATION=60  # 每次监控的持续时间，单位为秒
OUTPUT_FILE_PREFIX="system_monitor"
AUDIO_TYPES=("opus" "red" "ISAC" "G722" "ILBC" "PCMU" "PCMA")

monitor_system() {
    local pid_to_monitor=$1
    local output_file=$2

    # 初始化CSV文件
    echo "Timestamp,System CPU Usage,System Memory Usage,System I/O Read,System I/O Write,System Network In,System Network Out,Process CPU Usage,Process Memory Usage" > $output_file

    # 获取系统总内存
    TOTAL_MEM=$(grep MemTotal /proc/meminfo | awk '{print $2}')

    while true; do
        TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')

        # 系统CPU使用率
        SYS_CPU=$(top -bn1 | grep "Cpu(s)" | sed "s/.*, *\([0-9.]*\)%* id.*/\1/" | awk '{print 100 - $1}')

        # 系统内存使用率
        MEM_FREE=$(grep MemFree /proc/meminfo | awk '{print $2}')
        MEM_USED=$(($TOTAL_MEM - $MEM_FREE))
        MEM_USAGE=$(awk "BEGIN {print $MEM_USED/$TOTAL_MEM*100}")

        # 系统I/O使用情况
        IO_READ=$(iostat -d 1 1 | grep 'sda' | awk '{print $5}')
        IO_WRITE=$(iostat -d 1 1 | grep 'sda' | awk '{print $6}')

        # 系统网络使用情况
        NET_IN=$(cat /proc/net/dev | grep eth0 | awk '{print $2}')
        NET_OUT=$(cat /proc/net/dev | grep eth0 | awk '{print $10}')

        # 进程CPU和内存使用情况
        if [ -e /proc/$pid_to_monitor/stat ]; then
            PROC_STAT=($(cat /proc/$pid_to_monitor/stat))
            PROC_CPU=${PROC_STAT[13]}
            PROC_MEM=$(awk '/VmRSS/{print $2}' /proc/$pid_to_monitor/status)
        else
            PROC_CPU="N/A"
            PROC_MEM="N/A"
        fi

        # 写入CSV文件
        echo "$TIMESTAMP,$SYS_CPU,$MEM_USAGE,$IO_READ,$IO_WRITE,$NET_IN,$NET_OUT,$PROC_CPU,$PROC_MEM" >> $output_file

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


    PID_TO_MONITOR=$(ps aux | grep "$PROGRAM_NAME" | grep "$PROGRAM_ARGS" | grep -v grep | awk '{print $2}' | head -n 1)

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
    
    # 等待一段时间进行监控
    sleep $MONITOR_DURATION  # 监控60秒，可以根据需要调整

    # 停止监控
    pkill -P $$ monitor_system
    echo "Finished monitoring for AudioType $audio_type."
done
