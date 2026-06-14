#!/usr/bin/env python3
"""
analyze-error-log.py - 错误日志智能分析脚本

用法:
    python3 analyze-error-log.py [文件或目录路径]
    
功能:
    - 按报错模块汇总
    - 根因异常类型汇总
    - 按小时分布
    - 错误消息去重摘要
    - 自动处理中文乱码
"""

import sys
import os
import re
from collections import Counter
from datetime import datetime


def parse_error_log(filepath):
    """解析单个错误日志文件"""
    errors = {
        'modules': Counter(),        # 报错类名
        'causes': Counter(),         # Caused by 异常
        'hourly': Counter(),         # 按小时分布
        'messages': Counter(),       # 错误消息摘要
        'total_lines': 0,
        'error_lines': 0,
    }

    # 尝试多种编码
    for encoding in ['utf-8', 'gbk', 'gb2312', 'latin-1']:
        try:
            with open(filepath, 'r', encoding=encoding) as f:
                lines = f.readlines()
            break
        except (UnicodeDecodeError, UnicodeError):
            continue
    else:
        print(f"  ⚠ 无法解码: {filepath}")
        return errors

    errors['total_lines'] = len(lines)
    current_error = None

    for line in lines:
        line = line.rstrip('\n\r')

        # 匹配 ERROR 行（日志主行）
        m = re.match(r'^(\d{4}-\d{2}-\d{2})\s+(\d{2}):\d{2}:\d{2},\d+\s+\[\S+\]\s+ERROR\s+(\S+)\s*-\s*(.*)', line)
        if m:
            errors['error_lines'] += 1
            date, hour, module, msg = m.groups()
            errors['modules'][module] += 1
            errors['hourly'][f'{date} {hour}'] += 1

            # 提取错误消息语义摘要
            msg_short = msg.strip()
            # 截断超长消息
            if len(msg_short) > 120:
                msg_short = msg_short[:117] + '...'
            errors['messages'][msg_short] += 1
            current_error = module
            continue

        # 匹配 Caused by 行
        cm = re.match(r'^Caused by:\s+(.*)', line)
        if cm:
            cause = cm.group(1).strip()
            # 只保留异常类型名（去掉详细描述）
            cause_type = re.split(r':\s', cause)[0]
            errors['causes'][cause_type] += 1
            continue

        # 匹配堆栈中的根异常（有时 Caused by 前面还有异常）
        em = re.match(r'^([\w.]+(?:Exception|Error)):\s', line)
        if em and current_error and 'at ' not in line:
            errors['causes'][em.group(1)] += 1

        # 重置 current_error 标记（离开堆栈行）
        if current_error and not line.startswith('\t') and line.strip():
            current_error = None

    return errors


def print_report(filename, errors):
    """打印单个文件的报告"""
    print(f"\n{'━'*50}")
    print(f"  文件: {os.path.basename(filename)}")
    print(f"{'━'*50}")
    print(f"  总行数: {errors['total_lines']}  |  ERROR 行: {errors['error_lines']}")

    # 按模块统计
    print(f"\n  ▶ 报错类统计（按模块）:")
    if errors['modules']:
        for cls, cnt in errors['modules'].most_common():
            short_cls = cls.split('.')[-1]  # 只显示类名
            print(f"    {cnt:5d} 次  {short_cls}  ({cls})")
    else:
        print("    (无)")

    # 根因异常
    print(f"\n  ▶ 根因异常汇总:")
    if errors['causes']:
        for exc, cnt in errors['causes'].most_common():
            print(f"    {cnt:5d} 次  {exc}")
    else:
        print("    (无堆栈信息)")

    # 按小时分布
    print(f"\n  ▶ 按小时分布（TOP 10）:")
    if errors['hourly']:
        for ts, cnt in errors['hourly'].most_common(10):
            print(f"    {ts}:00 → {cnt:3d} 次")
    else:
        print("    (无)")

    # TOP 错误消息摘要
    print(f"\n  ▶ 错误消息示例（TOP 5）:")
    if errors['messages']:
        for msg, cnt in errors['messages'].most_common(5):
            print(f"    [{cnt:3d}次] {msg[:100]}")
    else:
        print("    (无)")


def main():
    target = sys.argv[1] if len(sys.argv) > 1 else '/Users/lanlan/t8/parkinglogs/tl'

    if os.path.isfile(target):
        files = [target]
    elif os.path.isdir(target):
        files = sorted([
            os.path.join(target, f)
            for f in os.listdir(target)
            if f.endswith('.log') and 'error' in f.lower()
        ])
    else:
        print(f"错误: {target} 不存在")
        sys.exit(1)

    if not files:
        print(f"在 {target} 中未找到错误日志文件")
        sys.exit(1)

    print("=" * 55)
    print("   错误日志智能分析报告")
    print(f"  扫描路径: {target}")
    print(f"  文件数:   {len(files)}")
    print(f"  生成时间: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
    print("=" * 55)

    all_modules = Counter()
    all_causes = Counter()

    for f in files:
        err = parse_error_log(f)
        print_report(f, err)
        all_modules += err['modules']
        all_causes += err['causes']

    # 多文件汇总
    if len(files) > 1:
        print(f"\n{'='*55}")
        print("   多文件汇总统计")
        print(f"{'='*55}")

        print(f"\n  ▶ 各文件错误总数:")
        for f in files:
            err = parse_error_log(f)
            print(f"    {os.path.basename(f):40s} ▶ {err['error_lines']:5d} 条错误")

        print(f"\n  ▶ 跨文件 TOP 报错类:")
        for cls, cnt in all_modules.most_common(10):
            short_cls = cls.split('.')[-1]
            print(f"    {cnt:5d} 次  {short_cls}")

        print(f"\n  ▶ 跨文件 TOP 异常:")
        for exc, cnt in all_causes.most_common(10):
            print(f"    {cnt:5d} 次  {exc}")


if __name__ == '__main__':
    main()
