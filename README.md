### 在线脚本执行

- 示例
    > -s 让 bash 读取 curl 传输的数据，-- 之后的内容是传递给脚本的参数，也可以不加参数只有 bash
```bash
# check 进程号
curl -sSL https://raw.githubusercontent.com/liwj-ai/scripts/main/check/check_pid.sh | bash -s -- 6139

# check 端口号
curl -sSL https://raw.githubusercontent.com/liwj-ai/scripts/main/check/check_port.sh | bash -s -- 6139

# check top5高内存消耗进程信息
curl -sSL https://raw.githubusercontent.com/liwj-ai/scripts/main/check/memtop.sh | bash -s -- 5

# check top5高cpu消耗进程信息
curl -sSL https://raw.githubusercontent.com/liwj-ai/scripts/main/check/cputop.sh | bash -s -- 5
```
