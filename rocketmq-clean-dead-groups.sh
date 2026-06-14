#!/bin/bash
# ============================================================
# RocketMQ 死消费组清理脚本（clean-dead-groups.sh）
# 用途：从标准输入读取 group 列表，逐组清理消费组 + RETRY/DLQ
# 使用：sort -u 4s.txt | bash clean-dead-groups.sh
# 或者：cat /tmp/clean-groups.txt | bash clean-dead-groups.sh
# 环境：RocketMQ 4.9.3, BusyBox 容器
# 注意：4.9.3 的 deleteSubGroup 会自动连带清理 RETRY/DLQ 主题
# ============================================================
NAMESRV="101.43.255.136:9876"
CLUSTER="rocketmq-cluster"
CONTAINER="rocketmq-a"
LOG_FILE="/tmp/rocketmq-clean-dead.log"

echo "$(date '+%Y-%m-%d %H:%M:%S') — 开始清理死消费组" | tee -a "$LOG_FILE"
echo "Namesrv: $NAMESRV | Cluster: $CLUSTER" | tee -a "$LOG_FILE"
echo "输入来源: 标准输入 (pipe/redirect)" | tee -a "$LOG_FILE"
echo "---" | tee -a "$LOG_FILE"

SUCCESS=0
FAIL=0

while IFS= read -r g; do
  # 跳过空行和注释
  [ -z "$g" ] && continue
  [[ "$g" == \#* ]] && continue

  echo -n "[$(date '+%H:%M:%S')] 清理 $g ... " | tee -a "$LOG_FILE"

  out=$(docker exec "$CONTAINER" bin/mqadmin deleteSubGroup \
    -n "$NAMESRV" -c "$CLUSTER" -g "$g" 2>&1 | grep -v "WARN No appenders")

  if echo "$out" | grep -q "success"; then
    echo "✅ 成功" | tee -a "$LOG_FILE"
    SUCCESS=$((SUCCESS + 1))
  else
    echo "❌ 失败" | tee -a "$LOG_FILE"
    echo "$out" | tee -a "$LOG_FILE"
    FAIL=$((FAIL + 1))
  fi
done

echo "===" | tee -a "$LOG_FILE"
echo "$(date '+%Y-%m-%d %H:%M:%S') — 清理完成" | tee -a "$LOG_FILE"
echo "成功: $SUCCESS | 失败: $FAIL" | tee -a "$LOG_FILE"
echo "完整日志: $LOG_FILE"
