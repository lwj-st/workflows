#!/usr/bin/env bash
# memtop.sh - 按内存(RSS)列出占用最高的进程
# 仅依赖: ps, awk, /proc/meminfo (系统自带)
#
# 用法:
#   ./memtop.sh        # 默认前 10
#   ./memtop.sh 20     # 前 20

set -euo pipefail

N="${1:-10}"
if ! [[ "$N" =~ ^[0-9]+$ ]] || [[ "$N" -lt 1 ]]; then
  echo "用法: $0 [数量]" >&2
  echo "  数量: 正整数，默认 10" >&2
  exit 1
fi

MEM_TOTAL_KB="$(awk '/^MemTotal:/ {print $2}' /proc/meminfo 2>/dev/null || echo 0)"

ps -eo pid,user,%mem,rss,args --no-headers 2>/dev/null | awk -v n="$N" -v mem_total_kb="$MEM_TOTAL_KB" '
function human_kb(kb) {
  if (kb >= 1048576) return sprintf("%.2f GiB", kb / 1048576)
  if (kb >= 1024)    return sprintf("%.2f MiB", kb / 1024)
  return sprintf("%.0f KiB", kb)
}
{
  pid = $1
  user = $2
  mempct = $3 + 0
  rss_kb = $4 + 0
  $1 = $2 = $3 = $4 = ""
  sub(/^[ \t]+/, "")
  cmd = $0
  count++
  pids[count] = pid
  users[count] = user
  mempcts[count] = mempct
  rsss[count] = rss_kb
  cmds[count] = cmd
}
END {
  if (count == 0) {
    print "未获取到进程列表" > "/dev/stderr"
    exit 1
  }
  # 按 RSS 降序（选择排序，无外部 sort）
  for (i = 1; i <= count; i++) {
    for (j = i + 1; j <= count; j++) {
      if (rsss[j] > rsss[i]) {
        t = rsss[i]; rsss[i] = rsss[j]; rsss[j] = t
        t = mempcts[i]; mempcts[i] = mempcts[j]; mempcts[j] = t
        t = pids[i]; pids[i] = pids[j]; pids[j] = t
        t = users[i]; users[i] = users[j]; users[j] = t
        t = cmds[i]; cmds[i] = cmds[j]; cmds[j] = t
      }
    }
  }
  show = (n < count ? n : count)
  printf "%-8s %-8s %6s %12s %s\n", "PID", "USER", "%MEM", "RSS", "COMMAND"
  printf "%-8s %-8s %6s %12s %s\n", "------", "--------", "------", "------------", "-------"
  total_rss = 0
  for (i = 1; i <= show; i++) {
    total_rss += rsss[i]
    printf "%-8s %-8s %5.1f%% %12s %s\n", pids[i], users[i], mempcts[i], human_kb(rsss[i]), cmds[i]
  }
  printf "\n共 %d 个进程，列表合计 RSS ≈ %s\n", show, human_kb(total_rss)
  if (mem_total_kb > 0)
    printf "整机 MemTotal: %s，列表合计约占 %.1f%%\n", human_kb(mem_total_kb), 100 * total_rss / mem_total_kb
}
'
