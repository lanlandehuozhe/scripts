#!/bin/bash
# 检查 RocketMQ 死消费组，输出 ≥N 天无活动的 group 列表
# 用法: bash rocketmq-check-dead-groups.sh [天数阈值，默认7]
# 输出: 标准输出（可 pipe 给清理脚本）

NAMESRV="101.43.255.136:9876"
CONTAINER="rocketmq-a"
DEAD_DAYS="${1:-7}"

docker exec "$CONTAINER" sh -c '
  DAYS='"$DEAD_DAYS"'
  grep -oE "consumerGroup=t8pkr_[a-zA-Z0-9_-]+" ~/logs/rocketmqlogs/broker.log |
    sort -u |
    while IFS="=" read _ group; do
      last_line=$(grep -F "consumerGroup=$group" ~/logs/rocketmqlogs/broker.log | tail -1)
      last_date=$(echo "$last_line" | awk "{print \$1}")
      t=$(date -d "$last_date" +%s 2>/dev/null)
      now=$(date +%s)
      days=$(( (now - t) / 86400 ))
      echo "$days|$group|$last_date"
    done' | sort -rn -t'|' -k1 | while IFS='|' read -r days group date; do
      if [ "$days" -ge "$DEAD_DAYS" ]; then
        echo "$group"
        echo "  ← $days 天前 ($date)  ≥${DEAD_DAYS}天 → 死组" >&2
      else
        echo "  $days 天前 ($date)  活跃中，跳过" >&2
      fi
    done
echo "" >&2
echo "---" >&2
echo "合计 $(docker exec "$CONTAINER" sh -c 'grep -oE "consumerGroup=t8pkr_" ~/logs/rocketmqlogs/broker.log | wc -l' 2>/dev/null) 条日志记录" >&2
