#!/bin/bash
RED='\033[0;31m'; YELLOW='\033[1;33m'; GREEN='\033[0;32m'
CYAN='\033[0;36m'; BOLD='\033[1m'; DIM='\033[2m'; NC='\033[0m'

TOTAL_STEPS=7; CURRENT_STEP=0

progress() {
  ((CURRENT_STEP++))
  local pct=$((CURRENT_STEP * 100 / TOTAL_STEPS))
  local filled=$((pct / 2))
  local empty=$((50 - filled))
  local bar=""
  for ((i=0; i<filled; i++)); do bar+="#"; done
  for ((i=0; i<empty; i++)); do bar+="."; done
  echo -e "\r${DIM}[${bar}] ${pct}%  $1${NC}"
}

RESULT_FILE=$(mktemp /tmp/hc.XXXXXX)
trap "rm -f $RESULT_FILE" EXIT

RISK_COUNT=0; WARN_COUNT=0
risk()   { echo -e " ${RED}[高危]${NC} $1" >> $RESULT_FILE; }
warn()   { echo -e " ${YELLOW}[警告]${NC} $1" >> $RESULT_FILE; }
ok()     { echo -e " ${GREEN}[正常]${NC} $1" >> $RESULT_FILE; }
info()   { echo -e " ${CYAN}[信息]${NC} $1" >> $RESULT_FILE; }
raw()    { echo -e "$1" >> $RESULT_FILE; }
risk_c() { risk "$1"; ((RISK_COUNT++)); }
warn_c() { warn "$1"; ((WARN_COUNT++)); }

raw "${BOLD}========================================${NC}"
raw "${BOLD} Linux 健康检查与安全风险评估${NC}"
raw "${BOLD} $(date '+%Y-%m-%d %H:%M:%S')${NC}"
raw "${BOLD}========================================${NC}"
raw "${CYAN}主机: $(hostname)${NC} | ${CYAN}内核: $(uname -r)${NC} | ${CYAN}系统: $(cat /etc/os-release 2>/dev/null | grep PRETTY_NAME | cut -d'"' -f2 || echo Unknown)${NC}"
[ "$(id -u)" -ne 0 ] && raw "${YELLOW}⚠ 非root运行，部分检查可能不完整${NC}"
raw ""

progress "1/7 系统资源"
raw "${BOLD}━━━ 1. 系统资源 ━━━${NC}"
LOAD1=$(awk '{print $1}' /proc/loadavg)
LOAD5=$(awk '{print $2}' /proc/loadavg)
LOAD15=$(awk '{print $3}' /proc/loadavg)
NCPU=$(nproc 2>/dev/null || grep -c processor /proc/cpuinfo)
raw " CPU: ${NCPU}核 | 负载: ${LOAD1}/${LOAD5}/${LOAD15}"
if awk "BEGIN{exit !($LOAD1 > $NCPU)}"; then
  warn_c "CPU负载过高 (${LOAD1}/${NCPU})"
else
  ok "CPU负载正常"
fi

MEM_TOTAL=$(free | awk '/Mem:/{print $2}')
MEM_USED=$(free | awk '/Mem:/{print $3}')
if [ "$MEM_TOTAL" -gt 0 ]; then
  MEM_PCT=$((MEM_USED * 100 / MEM_TOTAL))
  raw " 内存: ${MEM_USED}/${MEM_TOTAL} (${MEM_PCT}%)"
  [ "$MEM_PCT" -gt 90 ] && risk_c "内存使用超过90%" || { [ "$MEM_PCT" -gt 80 ] && warn_c "内存使用超过80%" || ok "内存使用正常"; }
else
  raw " 内存: 无法获取"; MEM_PCT=0
fi

SWAP_TOTAL=$(free | awk '/Swap:/{print $2}')
SWAP_USED=$(free | awk '/Swap:/{print $3}')
if [ "$SWAP_TOTAL" -gt 0 ]; then
  SWAP_PCT=$((SWAP_USED * 100 / SWAP_TOTAL))
  raw " Swap: ${SWAP_USED}/${SWAP_TOTAL} (${SWAP_PCT}%)"
  [ "$SWAP_PCT" -gt 50 ] && warn_c "Swap使用超过50%"
else
  raw " Swap: 未配置"
fi

raw ""
df -h -x tmpfs -x devtmpfs -x squashfs 2>/dev/null | awk 'NR==1 || /^[^F]/{printf " %-20s %6s %6s %6s %s\n",$6,$2,$3,$4,$5}' | head -20 >> $RESULT_FILE
df -h -x tmpfs -x devtmpfs -x squashfs 2>/dev/null | awk 'NR>1 && $5+0>90{print $6,$5}' | while read mp pct; do risk_c "磁盘${mp}使用率${pct}"; done
df -h -x tmpfs -x devtmpfs -x squashfs 2>/dev/null | awk 'NR>1 && $5+0>80 && $5+0<=90{print $6,$5}' | while read mp pct; do warn_c "磁盘${mp}使用率${pct}"; done
raw ""

INODE_ISSUE=$(df -i -x tmpfs -x devtmpfs -x squashfs 2>/dev/null | awk 'NR>1 && $5+0>80{print $6,$5}')
[ -n "$INODE_ISSUE" ] && echo "$INODE_ISSUE" | while read mp pct; do warn_c "inode ${mp}使用率${pct}"; done
raw ""

progress "2/7 安全风险"
raw "${BOLD}━━━ 2. 安全风险 ━━━${NC}"
if [ -f /etc/ssh/sshd_config ]; then
  PERMIT_ROOT=$(grep -i "^PermitRootLogin" /etc/ssh/sshd_config 2>/dev/null | awk '{print $2}')
  PASS_AUTH=$(grep -i "^PasswordAuthentication" /etc/ssh/sshd_config 2>/dev/null | awk '{print $2}')
  SSH_PORT=$(grep -i "^Port" /etc/ssh/sshd_config 2>/dev/null | awk '{print $2}')
  [ -z "$SSH_PORT" ] && SSH_PORT="22"
  raw " SSH端口: ${SSH_PORT}"
  [ "$PERMIT_ROOT" = "yes" ] && risk_c "SSH允许root直接登录" || ok "SSH root登录受限"
  [ "$PASS_AUTH" = "yes" ] && warn_c "SSH开启密码认证" || ok "SSH密码认证已关闭"
fi

raw ""
EMPTY_USERS=$(awk -F: '($2=="" || $2=="!") {print $1}' /etc/shadow 2>/dev/null)
[ -n "$EMPTY_USERS" ] && risk_c "空密码账户: $(echo $EMPTY_USERS | tr '\n' ' ')" || ok "无空密码账户"

ROOT_UIDS=$(awk -F: '$3==0 && $1!="root" {print $1}' /etc/passwd)
[ -n "$ROOT_UIDS" ] && risk_c "非root UID=0账户: $(echo $ROOT_UIDS | tr '\n' ' ')" || ok "无异常UID=0账户"

raw ""
FW_ACTIVE=false
if command -v firewall-cmd >/dev/null 2>&1 && firewall-cmd --state 2>/dev/null | grep -q running; then
  ok "firewalld已启用"; FW_ACTIVE=true
  firewall-cmd --list-ports 2>/dev/null | tr ' ' '\n' | grep -v '^$' | while read p; do info "firewalld开放端口: ${p}"; done
elif command -v ufw >/dev/null 2>&1 && ufw status 2>/dev/null | grep -q "active"; then
  ok "ufw已启用"; FW_ACTIVE=true
elif command -v iptables >/dev/null 2>&1 && iptables -L INPUT 2>/dev/null | grep -q "Chain"; then
  RULES=$(iptables -L INPUT 2>/dev/null | wc -l)
  if [ "$RULES" -gt 2 ]; then ok "iptables有规则(${RULES}行)"; FW_ACTIVE=true; fi
fi
[ "$FW_ACTIVE" = false ] && warn_c "未检测到活跃防火墙"

raw ""
raw " 监听端口:"
ss -tlnp 2>/dev/null | awk 'NR>1{print $4,$6}' | sed 's/.*://' | sort -n | uniq | head -20 | while read line; do raw "   $line"; done
raw ""

progress "3/7 系统服务"
raw "${BOLD}━━━ 3. 系统服务 ━━━${NC}"
FAILED_SERVICES=$(systemctl --failed 2>/dev/null | awk '/failed/{print $2}')
[ -n "$FAILED_SERVICES" ] && { warn_c "服务启动失败:"; echo "$FAILED_SERVICES" | while read s; do raw "  - ${s}"; done; } || ok "无失败的服务"

for svc in telnet.socket telnet.service xinetd.service vsftpd.service proftpd.service rsh.socket; do
  systemctl is-enabled "$svc" 2>/dev/null | grep -q enabled && risk_c "危险服务已启用: ${svc}"
done
raw ""

progress "4/7 内核与更新"
raw "${BOLD}━━━ 4. 内核与更新 ━━━${NC}"
RUNNING_KERNEL=$(uname -r)
INSTALLED_KERNEL=$(rpm -q kernel 2>/dev/null | sort -V | tail -1 | sed 's/kernel-//')
[ -z "$INSTALLED_KERNEL" ] && INSTALLED_KERNEL=$(dpkg -l linux-image-* 2>/dev/null | grep '^ii' | awk '{print $2}' | sort -V | tail -1 | sed 's/linux-image-//')
raw " 运行内核: ${RUNNING_KERNEL}"
[ -n "$INSTALLED_KERNEL" ] && [ "$RUNNING_KERNEL" != "$INSTALLED_KERNEL" ] && warn_c "新内核${INSTALLED_KERNEL}未重启" || ok "内核版本一致"

if command -v yum >/dev/null 2>&1; then
  SEC_UPDATES=$(yum check-update --security 2>/dev/null | grep -c "^[a-zA-Z0-9]")
  [ "$SEC_UPDATES" -gt 0 ] && warn_c "${SEC_UPDATES}个安全更新待安装" || ok "无待安装安全更新"
elif command -v apt >/dev/null 2>&1; then
  apt update -qq 2>/dev/null
  SEC_UPDATES=$(apt list --upgradable 2>/dev/null | grep -i secur | wc -l)
  [ "$SEC_UPDATES" -gt 0 ] && warn_c "${SEC_UPDATES}个安全更新待安装" || ok "无待安装安全更新"
fi

if [ -f /proc/uptime ]; then
  UPTIME_DAYS=$(awk '{print int($1/86400)}' /proc/uptime)
  raw " 运行: ${UPTIME_DAYS}天"
  [ "$UPTIME_DAYS" -gt 365 ] && warn_c "系统已运行超1年(${UPTIME_DAYS}天)"
fi
raw ""

progress "5/7 日志与异常"
raw "${BOLD}━━━ 5. 日志与异常 ━━━${NC}"
if [ -f /var/log/secure ]; then
  FAIL_LOGIN=$(grep "Failed password" /var/log/secure 2>/dev/null | wc -l)
  if [ "$FAIL_LOGIN" -gt 100 ]; then
    risk_c "登录失败${FAIL_LOGIN}次，疑似暴力破解"
    raw " 攻击来源TOP5:"
    grep "Failed password" /var/log/secure 2>/dev/null | grep -oP 'from \K[0-9.]+' | sort | uniq -c | sort -rn | head -5 | while read c ip; do raw "   ${ip}(${c}次)"; done
  elif [ "$FAIL_LOGIN" -gt 20 ]; then
    warn_c "登录失败${FAIL_LOGIN}次"
  else
    ok "登录失败次数正常(${FAIL_LOGIN})"
  fi
elif [ -f /var/log/auth.log ]; then
  FAIL_LOGIN=$(grep "Failed password" /var/log/auth.log 2>/dev/null | wc -l)
  [ "$FAIL_LOGIN" -gt 100 ] && risk_c "登录失败${FAIL_LOGIN}次，疑似暴力破解" || { [ "$FAIL_LOGIN" -gt 20 ] && warn_c "登录失败${FAIL_LOGIN}次" || ok "登录失败次数正常(${FAIL_LOGIN})"; }
else
  FAIL_LOGIN=$(journalctl _SYSTEMD_UNIT=sshd.service --since "24 hours ago" 2>/dev/null | grep -c "Failed password")
  [ "$FAIL_LOGIN" -gt 100 ] && risk_c "登录失败${FAIL_LOGIN}次" || { [ "$FAIL_LOGIN" -gt 20 ] && warn_c "登录失败${FAIL_LOGIN}次" || ok "登录失败次数正常(${FAIL_LOGIN})"; }
fi

OOM_COUNT=$(dmesg 2>/dev/null | grep -c "Out of memory")
[ "$OOM_COUNT" -gt 0 ] && warn_c "OOM记录${OOM_COUNT}次" || ok "无OOM记录"

DISK_ERR=$(dmesg 2>/dev/null | grep -ic "I/O error")
[ "$DISK_ERR" -gt 0 ] && risk_c "磁盘I/O错误${DISK_ERR}次"
raw ""

progress "6/7 可疑定时任务"
raw "${BOLD}━━━ 6. 可疑定时任务 ━━━${NC}"
SUSPECT_CRON=false
for user in $(cut -d: -f1 /etc/passwd); do
  CRONS=$(crontab -u "$user" -l 2>/dev/null | grep -v '^#' | grep -v '^$')
  if [ -n "$CRONS" ]; then
    if echo "$CRONS" | grep -qiE '(curl|wget|nc |ncat|/dev/tcp|base64|eval|python -c|perl -e)'; then
      risk_c "用户${user} crontab含可疑命令"; SUSPECT_CRON=true
    fi
  fi
done
for crondir in /etc/cron.d /etc/cron.daily /etc/cron.hourly /etc/cron.weekly /etc/cron.monthly; do
  [ -d "$crondir" ] || continue
  for f in "$crondir"/*; do
    [ -f "$f" ] || continue
    grep -qiE '(curl.*\||wget.*\||nc |ncat|/dev/tcp|base64.*-d|eval|python -c|perl -e)' "$f" 2>/dev/null && { risk_c "可疑cron: ${f}"; SUSPECT_CRON=true; }
  done
done
[ "$SUSPECT_CRON" = false ] && ok "未发现可疑定时任务"
raw ""

progress "7/7 网络安全"
raw "${BOLD}━━━ 7. 网络安全 ━━━${NC}"
raw " 活跃连接TOP10:"
ss -tn state established 2>/dev/null | awk 'NR>1{print $5}' | cut -d: -f1 | sort | uniq -c | sort -rn | head -10 | while read c ip; do raw "   ${ip}: ${c}连接"; done

SUSPECT_PROC=$(ps aux 2>/dev/null | grep -iE '(nc -l|ncat -l|/dev/tcp|socat.*LISTEN)' | grep -v grep)
[ -n "$SUSPECT_PROC" ] && risk_c "可疑进程(反向shell?): $(echo $SUSPECT_PROC | head -1)" || ok "未检测到可疑进程"
raw ""

raw "${BOLD}========================================${NC}"
raw "${BOLD} 检查汇总${NC}"
raw "${BOLD}========================================${NC}"
raw " ${RED}高危: ${RISK_COUNT}${NC} | ${YELLOW}警告: ${WARN_COUNT}${NC}"
[ "$RISK_COUNT" -gt 0 ] && raw "\n ${RED}⚠ 存在高危项目，请尽快处理${NC}"
[ "$WARN_COUNT" -gt 0 ] && [ "$RISK_COUNT" -eq 0 ] && raw "\n ${YELLOW}⚡ 存在警告项，建议关注${NC}"
[ "$RISK_COUNT" -eq 0 ] && [ "$WARN_COUNT" -eq 0 ] && raw "\n ${GREEN}✅ 系统状态良好${NC}"
raw "\n${CYAN}检查完成: $(date '+%Y-%m-%d %H:%M:%S')${NC}"

echo ""
cat $RESULT_FILE
