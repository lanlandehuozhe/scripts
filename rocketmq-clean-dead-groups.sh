#!/bin/bash
# RocketMQ 自包含清理脚本：检查+清理一步完成
# 用法: bash rocketmq-clean-dead-groups.sh [天数阈值，默认7]
#       会自动扫描 broker.log，只清理 ≥N 天无活动的死组

NAMESRV="101.43.255.136:9876"
CLUSTER="rocketmq-cluster"
CONTAINER="rocketmq-a"
DEAD_DAYS="${1:-7}"
LOG_FILE="/tmp/rocketmq-clean-dead.log"

echo "$(date '+%Y-%m-%d %H:%M:%S') — 清理≥${DEAD_DAYS}天无活动的消费组" | tee "$LOG_FILE"
echo "---" | tee -a "$LOG_FILE"

COUNT_TOTAL=0
COUNT_CLEAN=0
COUNT_SKIP=0
COUNT_FAIL=0

while IFS='|' read -r days group date; do
  COUNT_TOTAL=$((COUNT_TOTAL + 1))
  if [ "$days" -lt "$DEAD_DAYS" ]; then
    echo "$days 天前 跳过 $group (活跃中)" | tee -a "$LOG_FILE"
    COUNT_SKIP=$((COUNT_SKIP + 1))
    continue
  fi

  echo -n "$days 天前 清理 $group ... " | tee -a "$LOG_FILE"
  out=$(docker exec "$CONTAINER" bin/mqadmin deleteSubGroup \
    -n "$NAMESRV" -c "$CLUSTER" -g "$group" 2>&1 | grep -v "WARN No appenders")

  if echo "$out" | grep -q "success"; then
    echo "✅" | tee -a "$LOG_FILE"
    COUNT_CLEAN=$((COUNT_CLEAN + 1))
  else
    echo "❌" | tee -a "$LOG_FILE"
    echo "  $out" | tee -a "$LOG_FILE"
    COUNT_FAIL=$((COUNT_FAIL + 1))
  fi
done < <(
  docker exec "$CONTAINER" sh -c '
    DEAD='"$DEAD_DAYS"'
    grep -oE "consumerGroup=t8pkr_[a-zA-Z0-9_-]+" ~/logs/rocketmqlogs/broker.log |
      sort -u |
      while IFS="=" read _ group; do
        last_line=$(grep -F "consumerGroup=$group" ~/logs/rocketmqlogs/broker.log | tail -1)
        d=$(echo "$last_line" | awk "{print \$1}")
        ts=$(date -d "$d" +%s 2>/dev/null)
        now=$(date +%s)
        days=$(( (now - ts) / 86400 ))
        echo "$days|$group|$d"
      done
  '
)

echo "===" | tee -a "$LOG_FILE"
echo "总计: $COUNT_TOTAL | 已清理: $COUNT_CLEAN | 跳过(活跃): $COUNT_SKIP | 失败: $COUNT_FAIL" | tee -a "$LOG_FILE"
echo "日志: $LOG_FILE" | tee -a "$LOG_FILE"
