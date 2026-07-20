#!/usr/bin/env bash
# ============================================================================
#  cfst_push.sh  —  本机一键：CloudflareSpeedTest 测速 → 转为 WorkerVless2sub
#                    ADDCSV 格式 → 提交并 push 回仓库。
#
#  为什么需要它：
#    GitHub Actions 的 runner 出口到 Cloudflare 下载测速地址被拦截，
#    测出来的下载速度全是 0.00，无法做速度优选。
#    真正有意义的测速必须在【你自己的客户端网络】上跑，所以本脚本在你
#    本机执行，把"你网络环境最优的 IP"写回仓库，订阅链接永远不变。
#
#  用法：
#    GITHUB_TOKEN=ghp_xxx ./cfst_push.sh        # 用 token 推（任意机器）
#    ./cfst_push.sh                              # 用 SSH key 推（已配好 key 的机器）
#
#  产物：仓库根目录 best_ips.csv
#    格式：IP地址,端口,TLS,数据中心,下载速度(MB/s)   （worker ADDCSV 要求的格式）
#    内容：先放本机 CFST 实测 IP（你的网络最优），再合并仓库自带
#          addressescsv.csv 的精选 IP 作兜底，按 IP 去重。
# ============================================================================
set -euo pipefail

REPO="${CFST_REPO:-MarshallEriksen-Neura/WorkerVless2sub}"
TOKEN="${GITHUB_TOKEN:-}"
WORKDIR="${CFST_WORKDIR:-$HOME/.cfst_push}"

mkdir -p "$WORKDIR"
cd "$WORKDIR"

# ---- 1. 准备仓库 ----
if [ ! -d WorkerVless2sub/.git ]; then
  rm -rf WorkerVless2sub
  if [ -n "$TOKEN" ]; then
    git clone "https://${TOKEN}@github.com/${REPO}.git" WorkerVless2sub
  else
    git clone "git@github.com:${REPO}.git" WorkerVless2sub
  fi
fi
cd WorkerVless2sub
git checkout -q main 2>/dev/null || git checkout -q master 2>/dev/null
git pull --ff-only

# ---- 2. 下载 cfst（自动识别系统/架构）----
OS=$(uname -s | tr '[:upper:]' '[:lower:]')
ARCH=$(uname -m)
case "$ARCH" in x86_64|amd64) A=amd64;; arm64|aarch64) A=arm64;; *) echo "不支持的架构: $ARCH"; exit 1;; esac
case "$OS" in
  linux*) P=linux;;
  darwin*) P=darwin;;
  mingw*|msys*|cygwin*) P=windows;;
  *) echo "不支持的系统: $OS"; exit 1;;
esac
if [ "$P" = windows ]; then
  F="cfst_${P}_${A}.zip"
  CFST_BIN=./cfst.exe
else
  F="cfst_${P}_${A}.tar.gz"
  CFST_BIN=./cfst
fi
echo "== 下载 $F =="
URL="https://github.com/XIU2/CloudflareSpeedTest/releases/latest/download/$F"
if command -v gh >/dev/null 2>&1 && gh release download --repo XIU2/CloudflareSpeedTest --pattern "$F" --clobber; then
  :
elif command -v curl >/dev/null 2>&1; then
  curl -fL --connect-timeout 20 --retry 5 --retry-all-errors --retry-delay 2 -o "$F" "$URL"
elif command -v wget >/dev/null 2>&1; then
  wget -O "$F" "$URL"
else
  echo "缺少下载工具：需要 curl 或 wget"
  exit 1
fi
if [ "$P" = windows ]; then
  unzip -o "$F"
else
  tar -zxf "$F"
  chmod +x cfst
fi

# ---- 3. 跑测速（延迟 + 下载速度）----
echo "== 运行测速（延迟+速度，约 1-2 分钟）=="
"$CFST_BIN" -o result_raw.csv -tl 200 -dn 20 -sl 0.00

# ---- 4. 转换 CFST 原生输出 → ADDCSV 5 列格式 ----
# CFST 输出：IP地址,已发送,已接收,丢包率,平均延迟,下载速度(MB/s),地区码
awk -F',' 'NR==1{next}
{
  ip=$1; port="443"; tls="TRUE"; region=$7; speed=$6;
  if (speed+0==0) next;                       # 跳过速度为 0 的 IP
  printf "%s,%s,%s,%s,%s\n", ip, port, tls, region, speed;
}' result_raw.csv > /tmp/cfst_best.csv

# ---- 5. 合并仓库自带精选库（真速度兜底）----
# addressescsv.csv：IP地址,端口,回源端口,TLS,数据中心,地区,城市,TCP延迟,速度
if [ -f addressescsv.csv ]; then
  awk -F',' 'NR>1{
    ip=$1; port=$2; tls=toupper($4); region=$5; speed=$9;
    if (speed+0==0) next;
    printf "%s,%s,%s,%s,%s\n", ip, port, tls, region, speed;
  }' addressescsv.csv > /tmp/base_best.csv
else
  : > /tmp/base_best.csv
fi

# 先放本机实测（你的网络最优），再放精选库，按 IP 去重
{ echo "IP地址,端口,TLS,数据中心,下载速度(MB/s)"; cat /tmp/cfst_best.csv /tmp/base_best.csv; } > /tmp/merged.csv
awk -F',' 'NR==1{print;next} !seen[$1]++' /tmp/merged.csv > best_ips.csv

echo "== best_ips.csv 行数（含表头）: $(wc -l < best_ips.csv) =="
echo "== 本机实测有效 IP 数: $(wc -l < /tmp/cfst_best.csv) =="

# ---- 6. 提交并 push ----
git config user.name "Local CFST"
git config user.email "cfst@local"
git add best_ips.csv
if git diff --cached --quiet; then
  echo "无变化，跳过提交"
else
  git commit -m "Update best_ips.csv via local CFST ($(date +%F))"
  git push
fi
echo "DONE -> best_ips.csv 已更新并推送"
