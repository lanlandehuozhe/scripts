#!/usr/bin/env bash
# logsearch - 停车场日志IP搜索（交互/命令行双模式）
# 用法:
#   logsearch.sh                     # 交互模式，回车使用默认值
#   logsearch.sh <ip> [from_date] [to_date]
#     ip:        可选，默认 192.168.55.*
#     from_date: 可选，默认今天
#     to_date:   可选，默认等于 from_date（单日）
# 示例:
#   logsearch.sh 192.168.55.65 2026-06-13 2026-06-15
#
# 依赖: awk, macOS date (date -j)
# 日志文件: t8-camera-push.YYYY-MM-DD.N.log

set -euo pipefail

main() {
  local ip date_from date_to
  local files=()
  local log_pattern="t8-camera-push"

  # ---- 参数解析 ----
  if [[ $# -eq 0 ]]; then
    local today
    today=$(date +%Y-%m-%d)
    read -r -p "输入IP [192.168.55.*]: " ip
    ip=${ip:-192.168.55.*}
    read -r -p "起始日期 [$today]: " date_from
    date_from=${date_from:-$today}
    read -r -p "结束日期 [回车=单日]: " date_to
    date_to=${date_to:-$date_from}
  else
    ip="${1:-192.168.55.*}"
    date_from="${2:-$(date +%Y-%m-%d)}"
    date_to="${3:-$date_from}"
  fi

  # ---- IP 通配转正则 ----
  # 192.168.55.* -> 192\.168\.55\.[0-9]+
  local ip_regex="${ip//./\\.}"
  ip_regex="${ip_regex//\*/[0-9]+}"

  # ---- 文件列表 ----
  local d=$date_from
  while true; do
    for f in "$log_pattern.$d."*.log; do
      [[ -f "$f" ]] && files+=("$f")
    done
    [[ "$d" == "$date_to" ]] && break
    d=$(date -j -f "%Y-%m-%d" -v+1d "$d" "+%Y-%m-%d")
  done

  if [[ ${#files[@]} -eq 0 ]]; then
    echo "没有匹配的日志文件 ($date_from ~ $date_to)"
    return 1
  fi

  echo "IP: $ip  日期: $date_from ~ $date_to  (${#files[@]}个文件)"

  awk -F'[][()]|- ' -v OFS='\r\n' -v regex="$ip_regex" '
    $0 ~ regex " 上报" {print $1,$4,$6,$8,$10}
  ' "${files[@]}"
}

main "$@"
