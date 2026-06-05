cat > /tmp/gc_check.sh << 'EOF'
#!/bin/bash
echo "=========================================="
echo "          GC 健康诊断 v2"
echo "=========================================="
echo "时间: $(date '+%Y-%m-%d %H:%M:%S')"
echo ""

# 1. GC 模型（多方式探测）
echo "【1】GC 模型"
GCM=""
# 方式A：jcmd
if GCM=$(jcmd 1 VM.flags 2>/dev/null | grep -oE '\-XX:\+Use\w+GC' | head -1) && [ -n "$GCM" ]; then
  echo "  方式A: $GCM"
# 方式B：java -XX:+PrintFlagsFinal
elif GCM=$(java -XX:+PrintFlagsFinal -version 2>&1 | grep -m1 "UseParallelGC\|UseG1GC" | grep -oE '\-XX:\+Use\w+GC'); then
  echo "  方式B: $GCM"
# 方式C：从 JAVA_TOOL_OPTIONS 读
elif GCM=$(cat /proc/1/environ 2>/dev/null | tr '\0' '\n' | grep "JAVA_TOOL_OPTIONS" | grep -oE '\-XX:\+Use\w+GC'); then
  echo "  方式C: $GCM"
# 方式D：默认判断
else
  JAVA_VER=$(java -version 2>&1 | head -1)
  if echo "$JAVA_VER" | grep -q "1.8"; then
    GCM="-XX:+UseParallelGC (JDK8 默认)"
    echo "  方式D: $GCM"
  else
    GCM="-XX:+UseG1GC (JDK 默认)"
    echo "  方式D: $GCM"
  fi
fi
echo ""

# 2. Java 版本
echo "【2】Java 版本"
java -version 2>&1 | head -1
echo ""

# 3. 堆内存
echo "【3】堆内存"
jstat -gc 1 | tail -1 | awk '{
  printf "  Eden: %.1fMB / %.1fMB (%.0f%%)\n", $8/1024, $7/1024, $8/$7*100
  printf "  Old:  %.1fMB / %.1fMB (%.0f%%)\n", $10/1024, $9/1024, $10/$9*100
  printf "  Meta: %.1fMB / %.1fMB (%.0f%%)\n", $12/1024, $11/1024, $12/$11*100
}'
echo ""

# 4. GC 频率（20秒采样）
echo "【4】GC 频率（20秒采样）"
YGC1=$(jstat -gc 1 | tail -1 | awk '{print $13}')
YGCT1=$(jstat -gc 1 | tail -1 | awk '{print $14}')
sleep 20
YGC2=$(jstat -gc 1 | tail -1 | awk '{print $13}')
YGCT2=$(jstat -gc 1 | tail -1 | awk '{print $14}')
DG=$((YGC2-YGC1))
DT=$(echo "$YGCT1 $YGCT2" | awk '{print $2-$1}')
AVG=$(echo "$DG $DT" | awk '{if($1>0) printf "%.3f", $2/$1; else print "0"}')
echo "  Young GC: ${DG}次 / 20秒"
echo "  平均耗时: ${AVG}s"
echo ""

# 5. GC 日志
echo "【5】GC 日志"
if [ -f /logs/gc.log ]; then
  LINES=$(wc -l < /logs/gc.log)
  echo "  ✅ 文件存在，共 ${LINES} 行"
  LAST=$(tail -20 /logs/gc.log | grep "Times:" | awk -F'[=,]' '{gsub(/secs|real|user|sys/,""); sum+=$NF; count++; if($NF>max) max=$NF} END {printf "%.3fs avg, %.3fs max", sum/count, max}')
  echo "  最近暂停: $LAST"
else
  echo "  ❌ 无 gc.log"
fi
echo ""

# 6. 结论
echo "【6】结论"
if [ $DG -eq 0 ]; then
  echo "  🎯 优秀 - 无 GC 压力，低负载运行"
elif [ $DG -le 2 ]; then
  echo "  ✅ 良好 - GC 正常"
elif [ $DG -le 6 ]; then
  echo "  ⚠️ 一般 - 建议观察"
else
  echo "  🔴 需优化 - GC 偏多，考虑调整参数"
fi
echo "=========================================="
EOF
chmod +x /tmp/gc_check.sh
/tmp/gc_check.sh
