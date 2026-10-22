#!/bin/bash
# ============================================================
#  HKBT 自动伪装站点
#  在 V2bX 安装完成后调用：等证书 → 装依赖 → 拉代码 → 随机部署
#
#  单独运行： bash hkbt.sh
#  跳过部署： HKBT_SKIP=1 bash install.sh
#  指定密码： HKBT_PASSWORD='xxx' bash hkbt.sh
# ============================================================

red='\033[0;31m'
green='\033[0;32m'
yellow='\033[0;33m'
plain='\033[0m'

HKBT_REPO="${HKBT_REPO:-Minerchu/hkbt-deploy}"
HKBT_DIR="/opt/hkbt-deploy"
V2BX_CONF="/etc/V2bX/config.json"
PASS_FILE="/opt/hkbt-deploy/panel-password.txt"

info() { echo -e "${yellow}[HKBT]${plain} $*"; }
ok()   { echo -e "${green}[HKBT]${plain} $*"; }
err()  { echo -e "${red}[HKBT]${plain} $*"; }

[[ $EUID -ne 0 ]] && err "必须用 root 运行" && exit 1
[[ -f "$V2BX_CONF" ]] || { err "未找到 $V2BX_CONF，请先完成 V2bX 安装与配置"; exit 1; }

# ---------- 1. 确认节点配置存在 ----------
node_count=$(python3 - "$V2BX_CONF" <<'PY'
import json, sys
try:
    d = json.load(open(sys.argv[1]))
    print(len(d.get("Nodes") or []))
except Exception:
    print(0)
PY
)
if [[ "$node_count" == "0" ]]; then
    err "config.json 里没有节点配置，跳过网站部署"
    err "请先运行 V2bX 生成配置，或手动编辑 $V2BX_CONF"
    exit 1
fi

# ---------- 2. 等证书 ----------
cert_path=$(python3 - "$V2BX_CONF" <<'PY'
import json, sys
try:
    d = json.load(open(sys.argv[1]))
    n = (d.get("Nodes") or [{}])[0]
    print(n.get("CertConfig", {}).get("CertFile", "") or "")
except Exception:
    print("")
PY
)

if [[ -z "$cert_path" ]]; then
    err "节点没有配置证书路径（CertConfig.CertFile），无法部署 HTTPS 站点"
    exit 1
fi

info "等待证书签发：$cert_path"
for i in $(seq 1 60); do
    [[ -s "$cert_path" ]] && break
    sleep 3
done
if [[ ! -s "$cert_path" ]]; then
    err "180 秒内未等到证书，请检查：journalctl -u V2bX -n 50 --no-pager"
    err "常见原因：域名未解析到本机 / 面板节点未配置 / CertMode 为 none"
    exit 1
fi
ok "证书就绪"

# ---------- 3. 依赖 ----------
if ! command -v nginx >/dev/null 2>&1; then
    info "安装 Nginx"
    if command -v apt-get >/dev/null 2>&1; then
        apt-get update -qq >/dev/null 2>&1
        apt-get install -y -qq nginx >/dev/null 2>&1
    elif command -v yum >/dev/null 2>&1; then
        yum install -y nginx >/dev/null 2>&1
    fi
    command -v nginx >/dev/null 2>&1 || { err "Nginx 安装失败，请手动安装后重试"; exit 1; }
fi

if ! python3 -c "import flask" >/dev/null 2>&1; then
    info "安装 Flask"
    if command -v apt-get >/dev/null 2>&1; then
        apt-get install -y -qq python3-flask >/dev/null 2>&1
    fi
    python3 -c "import flask" >/dev/null 2>&1 || pip3 install flask >/dev/null 2>&1
    python3 -c "import flask" >/dev/null 2>&1 || { err "Flask 安装失败"; exit 1; }
fi

# ---------- 4. 拉取 hkbt 代码 ----------
if [[ ! -f "$HKBT_DIR/app.py" ]]; then
    info "下载 hkbt-deploy"
    mkdir -p "$HKBT_DIR"
    tmp=$(mktemp -d)
    if ! curl -fsSL --max-time 60 \
        "https://github.com/$HKBT_REPO/archive/refs/heads/master.tar.gz" \
        -o "$tmp/hkbt.tar.gz"; then
        err "下载失败，请检查网络或手动 git clone 到 $HKBT_DIR"
        rm -rf "$tmp"
        exit 1
    fi
    tar xzf "$tmp/hkbt.tar.gz" -C "$tmp" 2>/dev/null
    src=$(find "$tmp" -maxdepth 1 -type d -name "hkbt-deploy-*" | head -1)
    [[ -n "$src" ]] || { err "压缩包结构异常"; rm -rf "$tmp"; exit 1; }
    cp -r "$src"/. "$HKBT_DIR"/
    rm -rf "$tmp"
    ok "代码已就位"
else
    ok "已存在 $HKBT_DIR，跳过下载"
fi

# ---------- 5. 生成密码 ----------
if [[ -n "$HKBT_PASSWORD" ]]; then
    PASS="$HKBT_PASSWORD"
elif [[ -s "$PASS_FILE" ]]; then
    PASS=$(cat "$PASS_FILE")
else
    PASS=$(head -c 32 /dev/urandom | base64 | tr -dc 'A-Za-z0-9' | head -c 14)
    [[ ${#PASS} -lt 12 ]] && PASS="Hkbt@$(date +%s | tail -c 7)"
fi

# ---------- 6. 部署 ----------
info "开始部署（随机模板 + 随机品牌）"
cd "$HKBT_DIR" || exit 1
python3 app.py --init --auto --port 443 --password "$PASS"
rc=$?

if [[ $rc -ne 0 ]]; then
    err "部署未通过自检，详见 /var/log/hkbt-deploy.log"
    err "可用面板重新部署：https://<域名>/<admin_path>/"
fi

mkdir -p "$HKBT_DIR"
printf '%s\n' "$PASS" > "$PASS_FILE"
chmod 600 "$PASS_FILE"

# ---------- 7. 汇总 ----------
python3 - "$PASS_FILE" <<'PY'
import json, os, sys
try:
    c = json.load(open("/opt/hkbt-deploy/config.json"))
except Exception:
    sys.exit(0)
pw = ""
try:
    pw = open(sys.argv[1]).read().strip()
except Exception:
    pass
d = c.get("domain", "")
print()
print("=" * 58)
print("  伪装站点已就绪")
print("=" * 58)
print("  网站地址   https://%s/" % d)
print("  部署面板   https://%s%s/" % (d, c.get("admin_path", "")))
print("  面板密码   %s" % pw)
print("  网站名称   %s" % c.get("brand", ""))
print("  站点模板   %s" % c.get("template", ""))
print("  对外端口   443")
print("  代理端口   %s" % c.get("proxy_port", ""))
print("  代理路径   %s" % c.get("path", ""))
print("-" * 58)
print("  密码同时保存在 %s" % sys.argv[1])
print("=" * 58)
PY

ok "完成。浏览器打开 https://<你的域名>/ 应能看到企业站"
