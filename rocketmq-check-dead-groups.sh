#!/bin/bash
# ============================================================
# RocketMQ 死消费组检查脚本（check-dead-groups.sh）
# 用途：扫描 Broker 日志，查找最后活跃时间超过 N 天的消费组
# 环境：RocketMQ 4.9.3, BusyBox 容器
# ============================================================
NAMESRV="101.43.255.136:9876"
CLUSTER="rocketmq-cluster"
CONTAINER="rocketmq-a"
# 判断是否已死的天数阈值
DEAD_DAYS=${1:-7}

echo "=== RocketMQ 死消费组检查 ==="
echo "Namesrv: $NAMESRV | Cluster: $CLUSTER | 容器: $CONTAINER"
echo "阈值: $DEAD_DAYS 天无活动视为死组"
echo ""

docker exec "$CONTAINER" bash -c "
  NAMESRV='$NAMESRV'
  MADMIN='bin/mqadmin'

  echo '--- 正在分析 Broker 日志，提取每组最后活跃时间...'

  grep -o 'consumerGroup=t8pkr_[a-z0-9_-]*' ~/logs/rocketmqlogs/broker.log |
    sort -u |
    while IFS='=' read _ group; do
      last=\$(grep -F \"\$group\" ~/logs/rocketmqlogs/broker.log |
            awk '{print \$1}' | tail -1)
      echo \"\$last \$group\"
    done | sort -k1 |
    while read -r date group; do
      # 计算距今天数
      t=\$(date -d \"\$date\" +%s 2>/dev/null)
      now=\$(date +%s)
      days=\$(( (now - t) / 86400 ))
      label=''
      [ \$days -ge $DEAD_DAYS ] && label=' ← 死组'
      echo \"[\$days天前] \$date \$group\$label\"
    done
"

echo ""
echo "=== 检查完成 ==="
echo "标记 '← 死组' 的即为 ≥${DEAD_DAYS}天无活动的消费组"
echo "如需清理，执行: bash clean-dead-groups.sh < group-list.txt"
