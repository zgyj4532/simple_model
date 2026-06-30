#!/usr/bin/env bash
# ============================================================================
# demo.sh — simple_model 交互式演示
#
# 用法: bash demo.sh
#       (从项目根目录跑，会在 ./demo-tmp/ 创建一个临时项目)
#
# 这个脚本会带你走一遍所有核心特性，按 [ENTER] 一步步演示
# ============================================================================

set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"

# 颜色（如果 TTY 支持）
if [[ -t 1 ]]; then
    C_BOLD="\033[1m"
    C_DIM="\033[2m"
    C_GREEN="\033[32m"
    C_CYAN="\033[36m"
    C_YELLOW="\033[33m"
    C_RESET="\033[0m"
else
    C_BOLD=""; C_DIM=""; C_GREEN=""; C_CYAN=""; C_YELLOW=""; C_RESET=""
fi

DEMO_DIR="./demo-tmp"
SCRIPT="./bootstrap.sh"

# ---------- helpers ----------

# 等用户按 ENTER
pause() {
    if [[ -t 0 ]]; then
        echo ""
        echo -e "${C_DIM}  按 ENTER 继续，Ctrl+C 退出...${C_RESET}"
        read -r _
    else
        sleep 1
    fi
}

# 标题 + 说明
section() {
    local title="$1"
    echo ""
    echo -e "${C_BOLD}${C_CYAN}============================================================${C_RESET}"
    echo -e "${C_BOLD}  $title${C_RESET}"
    echo -e "${C_CYAN}============================================================${C_RESET}"
    echo ""
}

note() {
    echo -e "${C_DIM}  # $1${C_RESET}"
}

# 跑一条命令并显示
run() {
    echo -e "${C_YELLOW}\$ $*${C_RESET}"
    "$@"
}

# 跑一条命令但只在第一次显示
run_quiet() {
    "$@" > /dev/null 2>&1
}

# ---------- 0. 准备 ----------

clear
section "0. 准备：清理 + 创建临时项目"

note "清理旧 demo 目录"
rm -rf "$DEMO_DIR"

note "检查依赖（bash + jq）"
echo "  bash: $(bash --version | head -1)"
echo "  jq:   $(jq --version)"
echo "  gh:   $(gh --version 2>/dev/null | head -1 || echo 'not installed (optional)')"

pause

# ---------- 1. 初始化项目 ----------

section "1. init: 从模板创建项目"

note "用 web_spa 模板生成新项目"
run ./bootstrap.sh --init --template web_spa --output "$DEMO_DIR"
echo ""
note "看生成的结构"
ls -la "$DEMO_DIR" | head -15

pause

# ---------- 2. 看架构 ----------

section "2. visualization: 看项目架构 (给老板/甲方)"

note "生成可视化"
cd "$DEMO_DIR"
run "$OLDPWD/bootstrap.sh" --target viz
echo ""
note "生成的文档和图"
ls -la "$OLDPWD/$DEMO_DIR/docs/" 2>/dev/null
echo ""
echo -e "${C_DIM}  # docs/architecture.html 是单文件，可直接邮件给客户${C_RESET}"
echo -e "${C_DIM}  # docs/ARCHITECTURE.md 在 GitHub 自动渲染 Mermaid${C_RESET}"

pause

cd "$OLDPWD"

# ---------- 3. explain: AI agent 的杀手锏 ----------

section "3. explain: 给 AI agent 一个 component 的全部 context"

note "先跑 generate 生成 .ai/ 上下文"
cd "$DEMO_DIR"
run "$OLDPWD/bootstrap.sh" --target agents,context,queue --no-validate
echo ""
note "现在 --explain 看看一个 component"

cd "$DEMO_DIR"
run "$OLDPWD/bootstrap.sh" --explain LoginPage
echo ""
echo -e "${C_DIM}  # 这是 markdown 输出，给人类看${C_RESET}"
echo -e "${C_DIM}  # 加 --json 输出机器可读 JSON，给 AI agent 看${C_RESET}"

pause

# ---------- 4. status dashboard ----------

section "4. status: 项目进度 dashboard"

note "看项目状态"
cd "$DEMO_DIR"
run "$OLDPWD/bootstrap.sh" --status

pause

# ---------- 5. next: AI agent 拿下一个 task ----------

section "5. next: AI agent 拿下一个 todo"

note "AI agent 启动时第一件事"
cd "$DEMO_DIR"
run "$OLDPWD/bootstrap.sh" --next --json | jq '{id, priority, task, component, module}'
echo ""
echo -e "${C_DIM}  # AI agent 拿到这个 JSON 就能开始干活，不用读其他文件${C_RESET}"

pause

# ---------- 6. claim + complete: AI agent 工作流 ----------

section "6. AI agent 工作流: claim -> 写代码 -> complete"

note "AI agent 接下这个 task"
TASK_ID="page_login_submit"
cd "$DEMO_DIR"
run "$OLDPWD/bootstrap.sh" --claim "$TASK_ID"

note "AI agent 写代码... (这里我们跳过实际写代码)"
sleep 1

note "AI agent 标记完成"
cd "$DEMO_DIR"
run "$OLDPWD/bootstrap.sh" --complete "$TASK_ID"
echo ""
echo -e "${C_DIM}  # status 自动从 pending -> in_progress -> done${C_RESET}"
echo -e "${C_DIM}  # 解锁了下游 todo (unlocked:)${C_RESET}"

pause

# ---------- 7. lint + auto-fix ----------

section "7. lint --fix: 自动修复反模式"

note "故意制造一个反模式：加一个孤立 component"
cd "$DEMO_DIR"
python3 << 'EOF'
import json
with open('struct.json') as f: d = json.load(f)
d['modules'][0]['components'].append({
    "name": "OrphanComponent",
    "description": "故意制造的孤立 component，没有 import 也没 caller"
})
with open('struct.json', 'w') as f: json.dump(d, f, indent=2, ensure_ascii=False)
EOF
echo ""
echo "  → OrphanComponent 已加入"
echo ""

note "先跑 lint 看问题"
cd "$DEMO_DIR"
run "$OLDPWD/bootstrap.sh" --lint
echo ""

note "现在加 --fix 自动修"
cd "$DEMO_DIR"
run "$OLDPWD/bootstrap.sh" --lint --fix
echo ""

note "再次 lint 看是否修好"
cd "$DEMO_DIR"
run "$OLDPWD/bootstrap.sh" --lint | tail -3

pause

# ---------- 8. drift ----------

section "8. drift: schema ↔ 产物一致性"

note "改 struct.json 但不重新生成"
cd "$DEMO_DIR"
# touch struct.json 但不改内容 — 触发 drift
touch struct.json
run "$OLDPWD/bootstrap.sh" --drift | head -10

pause

# ---------- 9. 真实编译验证 (Rust) ----------

section "9. rust: 真实编译验证 (cargo test)"

note "如果想看 Rust 编译（需要 cargo），切换到 ML 例子"
cd "$OLDPWD"
note "用 ML 项目跑 rust 生成 + cargo test"
echo ""
echo -e "${C_DIM}  \$ cd /tmp && mkdir ml-test && cd ml-test${C_RESET}"
echo -e "${C_DIM}  \$ cp -r $OLDPWD/{bootstrap.sh,generators,specs,struct.json,struct.schema.json,.gitignore} .${C_RESET}"
echo -e "${C_DIM}  \$ ./bootstrap.sh --target rust --no-validate${C_RESET}"
echo -e "${C_DIM}  \$ cd generated/rust && cargo test   # 应该 91/91 通过${C_RESET}"
echo ""

pause

# ---------- 10. cleanup ----------

section "10. 清理"

note "删除 demo 目录"
cd "$OLDPWD"
rm -rf "$DEMO_DIR"

echo ""
echo -e "${C_GREEN}============================================================${C_RESET}"
echo -e "${C_GREEN}  Demo 完成！${C_RESET}"
echo -e "${C_GREEN}============================================================${C_RESET}"
echo ""
echo "  接下来可以："
echo "    1. 看 README.md 了解完整命令集"
echo "    2. ./bootstrap.sh --init --template web_spa --output ./my-app  真的建个项目"
echo "    3. 访问 https://github.com/silverenternal/simple_model 提 issue / PR"
echo ""
echo "  5 分钟玩完整个工具链，0 个 emoji，纯 ASCII CLI。"
echo ""