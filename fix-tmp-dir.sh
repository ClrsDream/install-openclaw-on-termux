#!/bin/bash
# 修复 openclaw 在 Termux 中的 /tmp 目录问题

echo "正在修复 openclaw 的 /tmp 目录问题..."

# 设置变量
NPM_GLOBAL="$HOME/.npm-global"
BASE_DIR="$NPM_GLOBAL/lib/node_modules/openclaw"
LOG_DIR="$HOME/openclaw-logs"

# 1. 创建必要的目录
echo "[1/3] 创建目录..."
mkdir -p "$LOG_DIR"
mkdir -p "$HOME/tmp"

# 2. 搜索并修复所有包含 /tmp/openclaw 的文件
echo "[2/3] 搜索并修复硬编码的 /tmp/openclaw 路径..."

cd "$BASE_DIR"
FILES_WITH_TMP=$(grep -rl "/tmp/openclaw" dist/ 2>/dev/null || true)

if [ -n "$FILES_WITH_TMP" ]; then
    echo "  找到需要修复的文件："
    for file in $FILES_WITH_TMP; do
        echo "    - $file"
        node -e "const fs = require('fs'); const file = '$BASE_DIR/$file'; let c = fs.readFileSync(file, 'utf8'); c = c.replace(/\/tmp\/openclaw/g, process.env.HOME + '/openclaw-logs'); fs.writeFileSync(file, c);"
    done
    echo "  ✓ 所有文件修复完成"
else
    echo "  ℹ 未找到需要修复的文件"
fi

# 3. 验证修复结果
echo "[3/3] 验证修复结果..."
REMAINING=$(grep -r "/tmp/openclaw" dist/ 2>/dev/null || true)
if [ -n "$REMAINING" ]; then
    echo "  ⚠ 警告：仍有文件包含 /tmp/openclaw"
    echo "  受影响的文件："
    echo "$REMAINING"
else
    echo "  ✓ 所有 /tmp/openclaw 路径已替换为 $HOME/openclaw-logs"
fi

echo ""
echo "✓ 修复完成！"
echo ""
echo "现在可以启动 openclaw："
echo "export PATH=$NPM_GLOBAL/bin:\$PATH"
echo "export TMPDIR=\$HOME/tmp"
echo "export OPENCLAW_GATEWAY_TOKEN=你的token"
echo "openclaw gateway --bind lan --port 18789 --token \$OPENCLAW_GATEWAY_TOKEN --allow-unconfigured"
