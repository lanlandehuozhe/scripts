#!/bin/bash
# analyze-error-log.sh - 解析 error 日志，汇总所有错误原因
# 用法: ./analyze-error-log.sh [文件路径]
# 默认处理 t8-pkr-error-*.log

LOG_DIR="${1:-/Users/lanlan/t8/parkinglogs/tl}"
cd "$LOG_DIR" 2>/dev/null || { echo "目录 $LOG_DIR 不存在"; exit 1; }

echo "══════════════════════════════════════════"
echo "   错误日志分析报告"
echo "   扫描路径: $LOG_DIR"
echo "══════════════════════════════════════════"

FILES=$(ls t8-pkr-error-*.log 2>/dev/null)
if [ -z "$FILES" ]; then
    echo "未找到错误日志文件"
    exit 1
fi

for f in $FILES; do
    echo ""
    echo "━━━ 文件: $f ━━━"
    total=$(wc -l < "$f" | tr -d ' ')
    echo "总行数: $total"

    echo ""
    echo "▶ 报错类统计（按模块）:"
    grep "ERROR " "$f" | sed 's/.*ERROR //' | sed 's/ - .*//' | sort | uniq -c | sort -rn | head -20 | \
        while read count cls; do
            printf "  %5d 次  %s\n" "$count" "$cls"
        done

    echo ""
    echo "▶ 根因异常汇总:"
    grep -A1 "Caused by: " "$f" | grep -E "(Exception|Error):" | sed 's/^.*Caused by: //' | sort | uniq -c | sort -rn | \
        while read count exc; do
            printf "  %5d 次  %s\n" "$count" "$exc"
        done

    echo ""
    echo "▶ 按小时分布:"
    grep "ERROR " "$f" | grep -oE "^[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}" | sed 's/ /T/' | sort -tT -k2 | uniq -c | sort -rn -k1 | head -15 | \
        while read count ts; do
            printf "  %s:00 → %3d 次\n" "${ts/T/ }" "$count"
        done

    echo ""
done

# 如果有多个文件，额外输出跨文件汇总
file_count=$(echo "$FILES" | wc -l | tr -d ' ')
if [ "$file_count" -gt 1 ]; then
    echo "══════════════════════════════════════════"
    echo "   多文件汇总统计"
    echo "══════════════════════════════════════════"
    echo ""
    echo "▶ 各文件错误总数:"
    for f in $FILES; do
        cnt=$(grep -c "ERROR " "$f" 2>/dev/null)
        echo "  $f ▶ $cnt 条错误"
    done
fi
