#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail

VERBOSE=0
DRY_RUN=0
UNINSTALL=0
FORCE_UPDATE=0
WITH_NODE=0
WITH_TMUX=0
START_GATEWAY=0
PURGE_CONFIG=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        --verbose|-v) VERBOSE=1; shift ;;
        --dry-run|-d) DRY_RUN=1; shift ;;
        --uninstall|-u) UNINSTALL=1; shift ;;
        --update|-U) FORCE_UPDATE=1; shift ;;
        --with-node) WITH_NODE=1; shift ;;
        --with-tmux) WITH_TMUX=1; shift ;;
        --start-gateway) START_GATEWAY=1; shift ;;
        --purge-config) PURGE_CONFIG=1; shift ;;
        --help|-h)
            echo "用法: $0 [选项]"
            echo "选项:"
            echo "  --verbose, -v        启用详细输出"
            echo "  --dry-run, -d        模拟运行，不执行实际命令"
            echo "  --uninstall, -u      卸载 nanobot（移除 venv 与 bashrc 注入）"
            echo "  --purge-config        卸载时同时删除 ~/.nanobot"
            echo "  --update, -U         强制升级 nanobot-ai"
            echo "  --with-node          安装 Node.js（仅 WhatsApp 通道需要）"
            echo "  --with-tmux          安装 tmux 与 termux-api（便于后台运行 gateway）"
            echo "  --start-gateway      安装后用 tmux 后台启动 nanobot gateway"
            exit 0
            ;;
        *)
            echo "未知选项: $1"
            echo "使用 --help 查看帮助"
            exit 1
            ;;
    esac
done

GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

if [ -t 1 ] && [ "$(tput colors 2>/dev/null || echo 0)" -ge 8 ]; then
    :
else
    GREEN=''
    BLUE=''
    YELLOW=''
    RED=''
    NC=''
fi

BASHRC="$HOME/.bashrc"
VENV_DIR="$HOME/.nanobot-venv"
LOG_DIR="$HOME/nanobot-logs"
LOG_FILE="$LOG_DIR/install.log"
PKG_UPDATE_FLAG="$HOME/.pkg_last_update_nanobot"

mkdir -p "$LOG_DIR" 2>/dev/null || true
touch "$BASHRC" 2>/dev/null || true

log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') $1" >> "$LOG_FILE"
}

run_cmd() {
    if [ $VERBOSE -eq 1 ]; then
        echo "[VERBOSE] $*"
    fi
    log "执行命令: $*"
    if [ $DRY_RUN -eq 1 ]; then
        echo "[DRY-RUN] 跳过: $*"
        return 0
    fi
    "$@"
}

ensure_pkg_fresh() {
    if [ ! -f "$PKG_UPDATE_FLAG" ] || [ $(($(date +%s) - $(stat -c %Y "$PKG_UPDATE_FLAG" 2>/dev/null || echo 0))) -gt 86400 ]; then
        echo -e "${YELLOW}更新包列表...${NC}"
        run_cmd pkg update -y
        run_cmd touch "$PKG_UPDATE_FLAG"
    fi
}

ensure_deps() {
    ensure_pkg_fresh
    local deps=("python" "git" "clang" "make" "pkg-config" "openssl" "libffi" "zlib" "libxml2" "libxslt")
    if [ $WITH_NODE -eq 1 ]; then
        deps+=("nodejs-lts")
    fi
    if [ $WITH_TMUX -eq 1 ] || [ $START_GATEWAY -eq 1 ]; then
        deps+=("tmux" "termux-api" "termux-tools")
    fi

    local missing=()
    for dep in "${deps[@]}"; do
        if ! dpkg -s "$dep" >/dev/null 2>&1; then
            missing+=("$dep")
        fi
    done

    if [ ${#missing[@]} -ne 0 ]; then
        echo -e "${YELLOW}安装依赖: ${missing[*]}${NC}"
        run_cmd pkg upgrade -y
        run_cmd pkg install -y "${missing[@]}"
    else
        echo -e "${GREEN}✅ 依赖已就绪${NC}"
    fi
}

ensure_python_version() {
    local major minor
    major="$(python -c 'import sys; print(sys.version_info[0])' 2>/dev/null || echo 0)"
    minor="$(python -c 'import sys; print(sys.version_info[1])' 2>/dev/null || echo 0)"
    if [ "$major" -lt 3 ] || { [ "$major" -eq 3 ] && [ "$minor" -lt 11 ]; }; then
        echo -e "${RED}错误：nanobot 需要 Python >= 3.11，当前: $(python -V 2>&1 || echo unknown)${NC}"
        exit 1
    fi
}

setup_venv() {
    if [ ! -d "$VENV_DIR" ]; then
        echo -e "${YELLOW}创建虚拟环境: $VENV_DIR${NC}"
        run_cmd python -m venv "$VENV_DIR"
    fi
    run_cmd "$VENV_DIR/bin/python" -m pip install -U pip setuptools wheel
}

pip_install_nanobot() {
    export TMPDIR="${TMPDIR:-$HOME/tmp}"
    mkdir -p "$TMPDIR" 2>/dev/null || true

    export CFLAGS="${CFLAGS:- -O2}"
    export LDFLAGS="${LDFLAGS:- -L$PREFIX/lib}"
    export CPPFLAGS="${CPPFLAGS:- -I$PREFIX/include}"
    export PKG_CONFIG_PATH="${PKG_CONFIG_PATH:-$PREFIX/lib/pkgconfig}"

    if [ $FORCE_UPDATE -eq 1 ]; then
        echo -e "${YELLOW}升级 nanobot-ai...${NC}"
        run_cmd "$VENV_DIR/bin/python" -m pip install -U nanobot-ai
    else
        echo -e "${YELLOW}安装 nanobot-ai...${NC}"
        run_cmd "$VENV_DIR/bin/python" -m pip install nanobot-ai
    fi
}

inject_shell() {
    local tmp
    tmp="$(mktemp)"
    cp "$BASHRC" "$tmp"

    sed -i '/\.nanobot-venv\/bin/d' "$tmp" || true
    sed -i '/alias nb=/d' "$tmp" || true
    sed -i '/alias nbstatus=/d' "$tmp" || true
    sed -i '/alias nbgw=/d' "$tmp" || true
    sed -i '/alias nblog=/d' "$tmp" || true
    sed -i '/alias nbkill=/d' "$tmp" || true

    cat >> "$tmp" <<EOT
export PATH="$VENV_DIR/bin:\$PATH"
alias nb="nanobot"
alias nbstatus="nanobot status"
alias nbgw="tmux new -d -s nanobot 'export TMPDIR=\$HOME/tmp; mkdir -p \$TMPDIR; nanobot gateway 2>&1 | tee $LOG_DIR/gateway.log'"
alias nblog="tmux attach -t nanobot"
alias nbkill="tmux kill-session -t nanobot 2>/dev/null || true; pkill -f 'nanobot gateway' 2>/dev/null || true"
EOT

    run_cmd cp "$tmp" "$BASHRC"
    rm -f "$tmp" 2>/dev/null || true
}

start_gateway_tmux() {
    if ! command -v tmux >/dev/null 2>&1; then
        echo -e "${RED}错误：未安装 tmux；请加 --with-tmux 或先 pkg install tmux${NC}"
        exit 1
    fi

    mkdir -p "$HOME/tmp" 2>/dev/null || true
    export TMPDIR="$HOME/tmp"

    tmux kill-session -t nanobot 2>/dev/null || true
    tmux new -d -s nanobot "export TMPDIR=\$HOME/tmp; mkdir -p \$TMPDIR; nanobot gateway 2>&1 | tee $LOG_DIR/gateway.log"

    if command -v termux-wake-lock >/dev/null 2>&1; then
        termux-wake-lock 2>/dev/null || true
    fi
}

uninstall_nanobot() {
    echo -e "${YELLOW}卸载 nanobot...${NC}"

    run_cmd tmux kill-session -t nanobot 2>/dev/null || true
    run_cmd pkill -f "nanobot gateway" 2>/dev/null || true

    if [ -f "$BASHRC" ]; then
        local tmp
        tmp="$(mktemp)"
        cp "$BASHRC" "$tmp"
        sed -i '/\.nanobot-venv\/bin/d' "$tmp" || true
        sed -i '/alias nb=/d' "$tmp" || true
        sed -i '/alias nbstatus=/d' "$tmp" || true
        sed -i '/alias nbgw=/d' "$tmp" || true
        sed -i '/alias nblog=/d' "$tmp" || true
        sed -i '/alias nbkill=/d' "$tmp" || true
        run_cmd cp "$tmp" "$BASHRC"
        rm -f "$tmp" 2>/dev/null || true
    fi

    if [ -d "$VENV_DIR" ]; then
        run_cmd rm -rf "$VENV_DIR"
    fi

    if [ $PURGE_CONFIG -eq 1 ] && [ -d "$HOME/.nanobot" ]; then
        run_cmd rm -rf "$HOME/.nanobot"
    fi

    echo -e "${GREEN}✅ 卸载完成${NC}"
}

clear
echo -e "${BLUE}=========================================${NC}"
echo -e "${BLUE}        nanobot Termux 安装脚本         ${NC}"
echo -e "${BLUE}=========================================${NC}"

if [ $DRY_RUN -eq 1 ]; then
    echo -e "${YELLOW}🔍 模拟运行模式：不执行实际命令${NC}"
fi

if [ $UNINSTALL -eq 1 ]; then
    uninstall_nanobot
    exit 0
fi

ensure_deps
ensure_python_version
setup_venv
pip_install_nanobot
inject_shell

echo -e "${GREEN}✅ nanobot 已安装${NC}"
echo -e "${BLUE}版本信息:${NC} $("$VENV_DIR/bin/nanobot" --version 2>/dev/null || echo unknown)"
echo -e "${YELLOW}下一步：执行 nanobot onboard 初始化，再编辑 ~/.nanobot/config.json 填入 API Key${NC}"

if [ $START_GATEWAY -eq 1 ]; then
    echo -e "${YELLOW}正在后台启动 nanobot gateway（tmux 会话: nanobot）...${NC}"
    start_gateway_tmux
    echo -e "${GREEN}✅ gateway 已启动：用 nblog 查看，用 nbkill 停止${NC}"
fi

