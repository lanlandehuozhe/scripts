#!/bin/bash
# RocketMQ 清理死消费组（从 stdin 读取 group 列表）
# 用法: bash rocketmq-check-dead-groups.sh 7 | bash rocketmq-clean-dead-groups.sh
#       或者: cat groups.txt | bash rocketmq-clean-dead-groups.sh
# 注意: 4.9.3 的 deleteSubGroup 自动连带清理 RETRY/DLQ 主题

NAMESRV="101.43.255.136:9876"
CLUSTER="rocketmq-cluster"
CONTAINER="rocketmq-a"
LOG_FILE="/tmp/rocketmq-clean-dead.log"

echo "$(date '+%Y-%m-%d %H:%M:%S') — 开始清理" | tee "$LOG_FILE"
echo "---" | tee -a "$LOG_FILE"

SUCCESS=0
FAIL=0

while IFS= read -r g; do
  [ -z "$g" ] && continue
  [[ "$g" == \#* ]] && continue
  [[ "$g" == "  "* ]] && continue            # 跳过 stderr 的注释行

  echo -n "[$(date '+%H:%M:%S')] 清理 $g ... " | tee -a "$LOG_FILE"

  out=$(docker exec "$CONTAINER" bin/mqadmin deleteSubGroup \
    -n "$NAMESRV" -c "$CLUSTER" -g "$g" 2>&1 | grep -v "WARN No appenders")

  if echo "$out" | grep -q "success"; then
    echo "✅" | tee -a "$LOG_FILE"
    SUCCESS=$((SUCCESS + 1))
  else
    echo "❌" | tee -a "$LOG_FILE"
    echo "$out" | tee -a "$LOG_FILE"
    FAIL=$((FAIL + 1))
  fi
done

echo "===" | tee -a "$LOG_FILE"
echo "$(date '+%Y-%m-%d %H:%M:%S') — 完成 | 成功: $SUCCESS | 失败: $FAIL" | tee -a "$LOG_FILE"
echo "日志: $LOG_FILE"
