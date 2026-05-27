#!/bin/bash

# 使用说明
if [ "$#" -lt 1 ]; then
    echo "用法: $0 <端口号或端口范围> [输出文件]"
    echo "示例: $0 8080"
    echo "示例: $0 8080-8085"
    echo "示例: $0 8080,9090-9092 output.txt"
    exit 1
fi

PORTS=$1
OUTPUT_FILE=$2

# 获取进程信息
function get_process_info_by_port() {
    local port=$1
    # 使用 ss 来查找监听在指定端口上的进程
    PID=$(ss -ltnp "sport = :$port" | awk 'NR==2 {print $6}' | cut -d',' -f2 | cut -d'=' -f2)

    if [ -z "$PID" ]; then
        echo "未找到对应的进程，请手动检查: ss -ltnp \"sport = :$port\"" 
        return
    fi

    # 打印进程基本信息
    echo "端口: $port"
    echo "进程PID: $PID"
    ps -p $PID -o pid,ppid,cmd,etime,%mem,%cpu

    # 获取进程启动时间
    Start_Time=$(ps -p $PID -o lstart |grep -v STARTED)
    echo "进程开始时间: $Start_Time"

    # 获取父进程信息
    PARENT_PID=$(ps -p $PID -o ppid=)
    if [ -n "$PARENT_PID" ]; then
        echo "父进程信息:"
        ps -p $PARENT_PID -o pid,cmd,etime

        # 获取进程启动时间
        Parent_Start_Time=$(ps -p $PARENT_PID -o lstart |grep -v STARTED)
        echo "父进程开始时间: $Parent_Start_Time"
    fi

    # 获取子进程信息
    echo "子进程信息:"
    pstree -p $PID

    # 获取进程打开的文件，忽略错误和警告
    echo "进程打开的文件:"
    lsof -p $PID 2>/dev/null || echo "[没有可打开的文件]"

    echo "--------------------------"
}

# 支持端口范围解析
function process_ports() {
    local ports=$1
    if [[ "$ports" == *-* ]]; then
        local start_port=$(echo $ports | cut -d'-' -f1)
        local end_port=$(echo $ports | cut -d'-' -f2)
        for port in $(seq $start_port $end_port); do
            get_process_info_by_port $port
        done
    else
        get_process_info_by_port $ports
    fi
}

# 保存输出到文件
function save_output_to_file() {
    if [ -n "$OUTPUT_FILE" ]; then
        echo "输出保存到文件: $OUTPUT_FILE"
        process_ports $PORTS | tee -a "$OUTPUT_FILE"
    else
        process_ports $PORTS
    fi
}

# 处理端口输入（支持多个端口和范围）
IFS=',' read -ra PORT_ARRAY <<< "$PORTS"
for port in "${PORT_ARRAY[@]}"; do
    save_output_to_file "$port"
done

