#!/bin/bash
echo ""
echo "========================================"
echo "  RocketMQ 日志 Pod 分析"
echo "========================================"
echo ""
LOGDIR="/run/containerd/io.containerd.runtime.v2.task/k8s.io"
# 1. 查找所有 rocketmq 日志文件
echo "🔍 第1步：查找 RocketMQ 日志文件..."
LOGFILES=$(find "$LOGDIR" -type f -name "rocketmq_client.log.*" 2>/dev/null)

if [ -z "$LOGFILES" ]; then
    echo "✅ 没有找到 RocketMQ 日志文件"
    exit 0
fi

# 提取 sandbox ID（不重复）
SANDBOX_IDS=$(echo "$LOGFILES" | sed "s|$LOGDIR/||" | cut -d'/' -f1 | sort -u)

FILE_COUNT=$(echo "$LOGFILES" | wc -l)
echo "找到 $FILE_COUNT 个日志文件"
echo ""

# 2. 获取 Pod 信息（用 crictl inspect，而不是 crictl pods）
echo "🔍 第2步：匹配 Pod 名称..."
echo ""

echo "========================================"
echo "  结果"
echo "========================================"
echo ""

TOTAL_SIZE=0

for sandbox_id in $SANDBOX_IDS; do
    if [ -z "$sandbox_id" ]; then
        continue
    fi
    
    # 用 crictl inspect 获取 Pod 信息（这个方法可行）
    POD_JSON=$(crictl inspect "$sandbox_id" 2>/dev/null)
    
    if [ -z "$POD_JSON" ]; then
        echo "❓ $sandbox_id (无法获取信息)"
        continue
    fi
    
    # 提取 Pod 名称
    POD_NAME=$(echo "$POD_JSON" | grep '"io.kubernetes.pod.name"' | head -1 | sed 's/.*: *"\([^"]*\)".*/\1/')
    NAMESPACE=$(echo "$POD_JSON" | grep '"io.kubernetes.pod.namespace"' | head -1 | sed 's/.*: *"\([^"]*\)".*/\1/')
    
    # 计算这个 Pod 的日志大小
    SIZE=$(find "$LOGDIR/$sandbox_id/rootfs/root/logs/rocketmqlogs/" -type f -name "rocketmq_client.log.*" -exec du -ch {} + 2>/dev/null | tail -1 | cut -f1)
    [ -z "$SIZE" ] && SIZE="0"
    
    # 统计文件数
    COUNT=$(find "$LOGDIR/$sandbox_id/rootfs/root/logs/rocketmqlogs/" -type f -name "rocketmq_client.log.*" 2>/dev/null | wc -l)
    
    echo "📦 $POD_NAME ($NAMESPACE)"
    echo "   Sandbox: $sandbox_id"
    echo "   文件数: $COUNT"
    echo "   大小:   $SIZE"
    echo ""
done

echo "========================================"
echo ""

# 3. 显示清理命令
echo "💡 清理命令（直接复制运行）："
echo ""

for sandbox_id in $SANDBOX_IDS; do
    if [ -z "$sandbox_id" ]; then
        continue
    fi
    
    echo "# === $sandbox_id ==="
    echo "crictl exec $sandbox_id  sh -c 'truncate -s 0 /root/logs/rocketmqlogs/rocketmq_client.log 2>/dev/null || true'"
    echo "crictl exec $sandbox_id  sh -c 'rm -f /root/logs/rocketmqlogs/rocketmq_client.log.* 2>/dev/null || true'"
    echo ""
done

echo "========================================"
echo "✅ 完成"
echo ""

# 4. 显示磁盘使用情况
echo "📊 当前磁盘使用情况："
df -h / | tail -1
SCRIPT_EOF

