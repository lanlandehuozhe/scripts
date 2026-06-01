#!/bin/bash
#########################################
# K8s 节点磁盘诊断脚本
# 使用方式: chmod +x disk_diagnose.sh && ./disk_diagnose.sh
#########################################

echo "========================================"
echo "  K8s 节点磁盘诊断报告"
echo "  $(date '+%Y-%m-%d %H:%M:%S')"
echo "========================================"

echo ""
echo "【1】磁盘整体使用情况"
echo "------------------------------"
df -h | grep -v "tmpfs\|overlay\|shm"

echo ""
echo "【2】根分区各目录占用 TOP10"
echo "------------------------------"
du -sh /* 2>/dev/null | sort -rh | head -10

echo ""
echo "【3】/var/lib 目录占用详情"
echo "------------------------------"
/Users/lanlan/.qclaw/workspace-agent-46553db1/disk_diagnose.sh
#!/bin/bash
#########################################
# K8s 节点磁盘诊断脚本
# 使用方式: chmod +x disk_diagnose.sh && ./disk_diagnose.sh
#########################################

echo "========================================"
echo "  K8s 节点磁盘诊断报告"
echo "  $(date '+%Y-%m-%d %H:%M:%S')"
echo "========================================"

echo ""
echo "【1】磁盘整体使用情况"
echo "------------------------------"
df -h | grep -v "tmpfs\|overlay\|shm"

echo ""
echo "【2】根分区各目录占用 TOP10"
echo "------------------------------"
du -sh /* 2>/dev/null | sort -rh | head -10

echo ""
echo "【3】/var/lib 目录占用详情"
echo "------------------------------"
:...skipping...
#!/bin/bash
#########################################
# K8s 节点磁盘诊断脚本
# 使用方式: chmod +x disk_diagnose.sh && ./disk_diagnose.sh
#########################################

echo "========================================"
echo "  K8s 节点磁盘诊断报告"
echo "  $(date '+%Y-%m-%d %H:%M:%S')"
echo "========================================"

echo ""
echo "【1】磁盘整体使用情况"
echo "------------------------------"
df -h | grep -v "tmpfs\|overlay\|shm"

echo ""
echo "【2】根分区各目录占用 TOP10"
echo "------------------------------"
du -sh /* 2>/dev/null | sort -rh | head -10

echo ""
echo "【3】/var/lib 目录占用详情"
echo "------------------------------"
du -sh /var/lib/* 2>/dev/null | sort -rh | head -10

echo ""
echo "【4】containerd/docker 镜像占用"
echo "------------------------------"
if command -v crictl &>/dev/null; then
  echo "[使用 crictl]"
  echo "运行中的容器数: $(crictl ps -a 2>/dev/null | tail -n +2 | wc -l)"
  echo "镜像数量: $(crictl images -q 2>/dev/null | wc -l)"
  echo "Docker磁盘占用:"
  docker system df 2>/dev/null
elif command -v ctr &>/dev/null; then
  echo "[使用 containerd ctr]"
  echo "镜像数量: $(ctr -n k8s.io images ls -q | wc -l)"
  echo "容器数量: $(ctr -n k8s.io containers ls -q | wc -l)"
fi
:...skipping...
#!/bin/bash
#########################################
# K8s 节点磁盘诊断脚本
# 使用方式: chmod +x disk_diagnose.sh && ./disk_diagnose.sh
#########################################

echo "========================================"
echo "  K8s 节点磁盘诊断报告"
echo "  $(date '+%Y-%m-%d %H:%M:%S')"
echo "========================================"

echo ""
echo "【1】磁盘整体使用情况"
echo "------------------------------"
df -h | grep -v "tmpfs\|overlay\|shm"

echo ""
echo "【2】根分区各目录占用 TOP10"
echo "------------------------------"
du -sh /* 2>/dev/null | sort -rh | head -10

echo ""
echo "【3】/var/lib 目录占用详情"
echo "------------------------------"
du -sh /var/lib/* 2>/dev/null | sort -rh | head -10

echo ""
echo "【4】containerd/docker 镜像占用"
echo "------------------------------"
if command -v crictl &>/dev/null; then
  echo "[使用 crictl]"
  echo "运行中的容器数: $(crictl ps -a 2>/dev/null | tail -n +2 | wc -l)"
  echo "镜像数量: $(crictl images -q 2>/dev/null | wc -l)"
  echo "Docker磁盘占用:"
  docker system df 2>/dev/null
elif command -v ctr &>/dev/null; then
  echo "[使用 containerd ctr]"
  echo "镜像数量: $(ctr -n k8s.io images ls -q | wc -l)"
  echo "容器数量: $(ctr -n k8s.io containers ls -q | wc -l)"
fi

echo ""
echo "【5】/var/log 日志占用"
echo "------------------------------"
du -sh /var/log/* 2>/dev/null | sort -rh | head -10

echo ""
echo "【6】/tmp 临时文件"
echo "------------------------------"
du -sh /tmp/* 2>/dev/null | sort -rh | head -10

echo ""
echo "【7】kubelet 磁盘阈值配置"
echo "------------------------------"
cat /var/lib/kubelet/kubeadm-flags.env 2>/dev/null
echo ""

echo ""
echo "【8】节点 Conditions 状态"
echo "------------------------------"
kubectl describe node $(hostname) 2>/dev/null | grep -A 8 "Conditions" | grep -v "^$"

echo ""
echo "【9】清理建议"
echo "------------------------------"
ROOT_USAGE=$(df -h / | awk 'NR==2 {print $5}' | sed 's/%//')
if [ "$ROOT_USAGE" -gt 80 ]; then
  echo "⚠️  根分区使用率 ${ROOT_USAGE}%，建议清理"
  echo "  - docker system prune -a -f"
  echo "  - journalctl --vacuum-time=7d"
  echo "  - kubectl delete pod --field-selector=status.phase==Succeeded -A"
else
  echo "✅ 根分区使用率 ${ROOT_USAGE}%，暂无异常"
fi

echo ""
echo "========================================"
echo "  诊断完成"
echo "========================================"
