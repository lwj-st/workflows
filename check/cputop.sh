#!/usr/bin/env bash
# cputop.sh - 按 CPU 占用列出最高的进程（采样间隔内平均值）
# 仅依赖: ps, awk, sleep, /proc (系统自带)
#
# 用法:
#   ./cputop.sh           # 默认前 10，采样 1 秒
#   ./cputop.sh 20        # 前 20
#   ./cputop.sh 10 2      # 前 10，采样 2 秒
#
# 说明:
#   %CPU 为采样区间内的平均占用；多核机器上单进程可超过 100%
#   （表示占用超过 1 个逻辑核）。列表合计可超过 100%。

set -euo pipefail

N="${1:-10}"
INTERVAL="${2:-1}"

if ! [[ "$N" =~ ^[0-9]+$ ]] || [[ "$N" -lt 1 ]]; then
  echo "用法: $0 [数量] [采样秒数]" >&2
  echo "  数量:     正整数，默认 10" >&2
  echo "  采样秒数: 正整数，默认 1" >&2
  exit 1
fi
if ! [[ "$INTERVAL" =~ ^[0-9]+$ ]] || [[ "$INTERVAL" -lt 1 ]]; then
  echo "采样秒数必须为正整数" >&2
  exit 1
fi

NCPU="$(nproc 2>/dev/null || awk '/^processor[ \t]*:/{c++} END{print c+0}' /proc/cpuinfo)"
[[ "$NCPU" -lt 1 ]] && NCPU=1

ps -eo pid,user,time,args --no-headers 2>/dev/null | awk -v n="$N" -v interval="$INTERVAL" -v ncpu="$NCPU" '
function cpu_total() {
  if ((getline line < "/proc/stat") <= 0) return -1
  close("/proc/stat")
  sub(/^cpu /, "", line)
  t = 0
  for (i = 1; i <= split(line, a); i++) t += a[i] + 0
  return t
}
function proc_ticks(pid,   f, line, file) {
  file = "/proc/" pid "/stat"
  if ((getline line < file) <= 0) { close(file); return -1 }
  close(file)
  if (!match(line, /\) /)) return -1
  split(substr(line, RSTART + RLENGTH), f, " ")
  return f[12] + f[13] + 0
}
{
  pid = $1
  user = $2
  time = $3
  $1 = $2 = $3 = ""
  sub(/^[ \t]+/, "")
  cmd = $0
  count++
  pids[count] = pid
  users[count] = user
  times[count] = time
  cmds[count] = cmd
  t0[pid] = proc_ticks(pid)
}
END {
  if (count == 0) {
    print "未获取到进程列表" > "/dev/stderr"
    exit 1
  }
  total0 = cpu_total()
  if (total0 < 0) {
    print "无法读取 /proc/stat" > "/dev/stderr"
    exit 1
  }
  system("sleep " interval)
  total1 = cpu_total()
  if (total1 <= total0) {
    print "CPU 采样失败（间隔过短或系统繁忙）" > "/dev/stderr"
    exit 1
  }
  total_delta = total1 - total0
  valid = 0
  for (i = 1; i <= count; i++) {
    pid = pids[i]
    if (!(pid in t0)) continue
    t1 = proc_ticks(pid)
    if (t0[pid] < 0 || t1 < 0) continue
    delta = t1 - t0[pid]
    if (delta < 0) continue
    valid++
    cpupcts[valid] = 100 * delta / total_delta
    pids2[valid] = pid
    users2[valid] = users[i]
    times2[valid] = times[i]
    cmds2[valid] = cmds[i]
  }
  if (valid == 0) {
    print "无有效 CPU 采样数据" > "/dev/stderr"
    exit 1
  }
  for (i = 1; i <= valid; i++) {
    for (j = i + 1; j <= valid; j++) {
      if (cpupcts[j] > cpupcts[i]) {
        t = cpupcts[i]; cpupcts[i] = cpupcts[j]; cpupcts[j] = t
        t = pids2[i]; pids2[i] = pids2[j]; pids2[j] = t
        t = users2[i]; users2[i] = users2[j]; users2[j] = t
        t = times2[i]; times2[i] = times2[j]; times2[j] = t
        t = cmds2[i]; cmds2[i] = cmds2[j]; cmds2[j] = t
      }
    }
  }
  show = (n < valid ? n : valid)
  printf "采样间隔: %d 秒 | 逻辑 CPU: %d 核\n\n", interval, ncpu
  printf "%-8s %-8s %8s %10s %s\n", "PID", "USER", "%CPU", "TIME", "COMMAND"
  printf "%-8s %-8s %8s %10s %s\n", "------", "--------", "--------", "----------", "-------"
  sum_cpu = 0
  for (i = 1; i <= show; i++) {
    sum_cpu += cpupcts[i]
    printf "%-8s %-8s %7.1f%% %10s %s\n", pids2[i], users2[i], cpupcts[i], times2[i], cmds2[i]
  }
  printf "\n共 %d 个进程，列表合计 %CPU ≈ %.1f%%\n", show, sum_cpu
  printf "（多核下多进程合计可大于 100%%；单核持续满载的单进程约 100%%）\n"
}
'
