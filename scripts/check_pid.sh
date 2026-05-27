#!/bin/bash

# 获取容器进程信息
get_container_info(){
  id=$1  
  echo "检测到 containerd 容器 ID: $id"
  echo "对应的容器信息如下："
  docker ps --filter "id=$id"
  echo "查看容器详细信息："
  echo "docker inspect $id "
}
# 函数：获取进程信息
get_process_info() {
    local pid=$1

    if [ ! -d /proc/$pid ]; then
        echo "进程 $pid 不存在"
        return
    fi

    # 进程基本信息
    local ppid=$(ps -o ppid= -p $pid)
    local cmd=$(ps -o cmd= -p $pid)
    local ppid_cmd=$(ps -o cmd= -p $ppid)
    local start_time=$(ps -o lstart= -p $pid)
    local ppid_start_time=$(ps -o lstart= -p $ppid)
    local mem_usage=$(ps -o %mem= -p $pid)
    local cpu_usage=$(ps -o %cpu= -p $pid)
    local status=$(ps -o stat= -p $pid)
    local user=$(ps -o user= -p $pid)
    local thread_count=$(ps -o nlwp= -p $pid)

    # 获取子进程（优先使用 pstree 命令）
    local child_info=""
    if command -v pstree > /dev/null; then
        # 如果 pstree 命令存在，使用它获取父子进程结构
        child_info=$(pstree -p $pid)
    else
        # 如果 pstree 不存在，使用 ps --ppid 来获取子进程
        local child_pids=$(ps --ppid $pid -o pid= | tr '\n' ' ')
        if [ -z "$child_pids" ]; then
            child_info="[No child processes]"
        else
            for child_pid in $child_pids; do
                child_info+="PID $child_pid: $(ps -o cmd= -p $child_pid)\n"
            done
        fi
    fi

    # 获取进程占用的文件
    local open_files=$(lsof -p $pid 2>/dev/null | awk '{print $9}' | sed '/^$/d')

    # 获取网络连接（与该进程相关）
    local net_connections=$(netstat -tulnp 2>/dev/null | grep $pid)

    echo "PID: $pid"
    echo "PPID: $ppid"
    echo "Command: $cmd"
    echo "Parent Command: $ppid_cmd"
    echo "Start Time: $start_time"
    echo "Parent Start Time: $ppid_start_time"
    echo "Memory Usage: $mem_usage%"
    echo "CPU Usage: $cpu_usage%"
    echo "Status: $status"
    echo "User: $user"
    echo "Thread Count: $thread_count"
    echo "Child Processes:"
    echo -e "$child_info" | sed 's/^/    /'   # 缩进子进程信息
    echo "Open Files:"
    if [ -z "$open_files" ]; then
        echo "    [No open files]"
    else
        echo "$open_files" | sed 's/^/    /'
    fi
    echo "Network Connections:"
    if [ -z "$net_connections" ]; then
        echo "    [No network connections]"
    else
        echo "$net_connections" | sed 's/^/    /'
    fi
    echo "----------------------------------------"
    
    local id=$(echo "$cmd $ppid_cmd" | grep -oP '(?<=-id )[a-f0-9]{64}')
    if [[ -n "$id" ]]; then
       get_container_info $id
    fi    
}


# 函数：处理范围内的进程信息
process_range() {
    local start_pid=$1
    local end_pid=$2
    local output_file=$3

    for ((pid=start_pid; pid<=end_pid; pid++)); do
        info=$(get_process_info $pid)
        echo "$info"
        if [ -n "$output_file" ]; then
            echo "$info" >> "$output_file"
        fi
    done
}

# 主函数
main() {
    if [ $# -lt 1 ]; then
        echo "用法: $0 <进程号或进程号范围> [输出文件]"
        exit 1
    fi

    # 解析输入
    pids=$1
    output_file=$2

    if [[ "$pids" == *"-"* ]]; then
        start_pid=$(echo $pids | cut -d '-' -f 1)
        end_pid=$(echo $pids | cut -d '-' -f 2)
        process_range $start_pid $end_pid $output_file
    else
        # 如果没有输出文件参数，则仅打印到控制台
        if [ -z "$output_file" ]; then
            get_process_info $pids
        else
            # 如果提供了输出文件，则同时打印到控制台并写入文件
            get_process_info $pids | tee -a "$output_file"
        fi
    fi
}
# 调用主函数
main "$@"
