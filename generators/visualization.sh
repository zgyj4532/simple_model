#!/usr/bin/env bash
# generators/visualization.sh — 交互式架构可视化（甲方展示用）
# 输出 docs/ARCHITECTURE.md + docs/*.mmd + docs/architecture.html
#
# architecture.html 现在是一个 single-file interactive SPA：
#   - 头部 + 暗色模式开关
#   - 统计面板（模块/组件/todo/blocker 数 + 完成进度）
#   - 左侧：搜索框 + 过滤器 + 组件清单
#   - 中央：Mermaid 图（可点击节点 → 右侧详情面板）
#   - 右侧：组件详情（描述/模块/导出/导入/todos）
#   - 底部：wave 时间轴（按 blocker DAG 切波）
#   - 全部 inline JS/CSS，仅 Mermaid 走 CDN
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/_lib.sh"

DOCS_DIR="$OUTPUT_DIR/docs"
mkdir -p "$DOCS_DIR"

if [[ "${PLAN_ONLY:-0}" == "1" ]]; then
    echo "  PLAN: $DOCS_DIR/ARCHITECTURE.md"
    echo "  PLAN: $DOCS_DIR/architecture.html"
    echo "  PLAN: $DOCS_DIR/module-graph.mmd"
    echo "  PLAN: $DOCS_DIR/phase-pipeline.mmd"
    echo "  PLAN: $DOCS_DIR/todo-blocker.mmd"
    exit 0
fi

PROJ_DESC=$(jq -r '.description // ""' "$STRUCT_FILE")
PHASE_COUNT=$(jq '.phases // [] | length' "$STRUCT_FILE")

# ---------- 公共 jq 投影 ----------
# data_blob.json: 完整项目状态（前端 JS 用），结构 = {modules, components, todos, phases, stats, waves}
build_data_blob() {
    local out="$1"
    jq '. as $orig
        | {
            schema_version: $orig.schema_version,
            description:    ($orig.description // ""),
            modules: [
                ($orig.modules // [])[] | {
                    name, description,
                    language:        (.language // "any"),
                    component_count: (.components | length),
                    todo_count:      ([.components[].todos // [] | length] | add // 0),
                    components: [.components[]? | {
                        name, description,
                        exports:  (.exports  // []),
                        imports:  (.imports  // .depends_on // []),
                        optional: (.optional // false),
                        todos:    (.todos // [])
                    }]
                }
            ],
            components: [
                ($orig.modules // [])[] as $m
                | $m.components[]?
                | {
                    name, description, module: $m.name,
                    language: ($m.language // "any"),
                    exports:  (.exports  // []),
                    imports:  (.imports  // .depends_on // []),
                    optional: (.optional // false),
                    todos:    (.todos // [])
                }
            ],
            todos: [
                ($orig.modules // [])[] as $m
                | $m.components[]?.todos[]?
                | . + {component: ("?"), module: $m.name}
            ],
            phases: [
                ($orig.phases // [])[] | {
                    phase, order, mode, description,
                    core_components:    (.core_components    // []),
                    optional_components:(.optional_components // [])
                }
            ]
        }
        | .stats = {
            module_count:    (.modules | length),
            component_count: ([.modules[].components // [] | length] | add // 0),
            todo_count:      ([.modules[].components[].todos // [] | length] | add // 0),
            todo_done:       ([.modules[].components[].todos[]? | select(.status == "done")] | length),
            todo_pending:    ([.modules[].components[].todos[]? | select(.status != "done")] | length),
            blocker_count:   ([.modules[].components[].todos[]?.blocks[]? // empty] | length),
            optional_count:  ([.modules[].components[]? | select(.optional == true)] | length),
            phase_count:     (.phases | length)
        }
    ' "$STRUCT_FILE" > "$out"
}

# ---------- 1. module-graph.mmd ----------
{
    echo "graph TD"
    echo "  classDef module fill:#e1f5ff,stroke:#01579b,stroke-width:2px"
    echo "  classDef component fill:#fff9c4,stroke:#f57f17,stroke-width:1px"
    echo "  classDef optional fill:#f5f5f5,stroke:#9e9e9e,stroke-dasharray: 5 5"
    echo ""

    while IFS=$'\t' read -r mi mname mdesc; do
        echo "  ${mname}[\"[MOD] ${mname}\"]:::module"
        echo "  click ${mname} callModuleClick"
    done < <(iter_modules)

    while IFS=$'\t' read -r mi mname mdesc; do
        while IFS=$'\t' read -r ci cname cdesc; do
            style=":::component"
            opt=$(jq -r ".modules[$mi].components[$ci].optional // false" "$STRUCT_FILE")
            [[ "$opt" == "true" ]] && style=":::optional"
            echo "  ${cname}[\"[CFG] ${cname}\"]${style}"
            echo "  ${mname} --> ${cname}"
            echo "  click ${cname} callOnClick"
        done < <(iter_components "$mi")
    done < <(iter_modules)

    echo ""
    while IFS=$'\t' read -r mi mname mdesc; do
        while IFS=$'\t' read -r ci cname cdesc; do
            imports_json=$(jq -c ".modules[$mi].components[$ci].imports // .modules[$mi].components[$ci].depends_on // []" "$STRUCT_FILE")
            while IFS= read -r dep; do
                [[ -z "$dep" ]] && continue
                echo "  ${cname} -.uses.-> ${dep}"
            done < <(echo "$imports_json" | jq -r '.[]')
        done < <(iter_components "$mi")
    done < <(iter_modules)
} > "$DOCS_DIR/module-graph.mmd"
say "$DOCS_DIR/module-graph.mmd"

# ---------- 2. phase-pipeline.mmd ----------
{
    echo "flowchart LR"
    echo "  classDef phase fill:#c8e6c9,stroke:#1b5e20,stroke-width:2px"
    echo ""

    if [[ $PHASE_COUNT -gt 0 ]]; then
        prev=""
        jq -r '.phases // [] | to_entries[] | "\(.key)\t\(.value.phase)\t\(.value.description)\t\(.value.mode)"' "$STRUCT_FILE" | while IFS=$'\t' read -r idx pname pdesc pmode; do
            echo "  P${idx}[\"[CFG] ${pname}<br/><i>${pmode}</i>\"]:::phase"
            [[ -n "$prev" ]] && echo "  ${prev} --> P${idx}"
            prev="P${idx}"
        done
    else
        echo "  P0[\"(no phases defined)\"]:::phase"
    fi
} > "$DOCS_DIR/phase-pipeline.mmd"
say "$DOCS_DIR/phase-pipeline.mmd"

# ---------- 3. todo-blocker.mmd ----------
{
    echo "graph LR"
    echo "  classDef high fill:#ffcdd2,stroke:#b71c1c"
    echo "  classDef medium fill:#fff9c4,stroke:#f57f17"
    echo "  classDef low fill:#c8e6c9,stroke:#1b5e20"
    echo ""

    TMP=$(mktemp)
    jq -r '
        .modules[] | .components[] | .todos[]? |
        [.id, (.priority // "medium")] | @tsv
    ' "$STRUCT_FILE" > "$TMP"

    while IFS=$'\t' read -r tid pri; do
        [[ -z "$tid" ]] && continue
        cls="medium"
        [[ "$pri" == "high" ]] && cls="high"
        [[ "$pri" == "low" ]] && cls="low"
        echo "  ${tid}[\"${tid}<br/><i>${pri}</i>\"]:::${cls}"
    done < "$TMP"
    rm -f "$TMP"

    echo ""
    jq -r '
        (.modules // []) | .[] | (.components // []) | .[] | (.todos // []) | .[]? |
        select(.blocks) | [.id, (.blocks | join(","))] | @tsv
    ' "$STRUCT_FILE" | while IFS=$'\t' read -r src targets; do
        [[ -z "$src" ]] && continue
        IFS=',' read -ra arr <<< "$targets"
        for t in "${arr[@]}"; do
            [[ -n "$t" ]] && echo "  ${src} --> ${t}"
        done
    done
} > "$DOCS_DIR/todo-blocker.mmd"
say "$DOCS_DIR/todo-blocker.mmd"

# ---------- 4. ARCHITECTURE.md ----------
{
    echo "# Architecture Overview"
    echo ""
    echo "> Auto-generated from \`$STRUCT_FILE\`"
    echo ""
    echo "$PROJ_DESC"
    echo ""
    echo "## [DOCS] Module / Component Graph"
    echo ""
    echo "_黄色 = 核心组件 · 灰色虚线 = 可选组件 · 蓝色 = 模块_"
    echo ""
    echo '```mermaid'
    cat "$DOCS_DIR/module-graph.mmd"
    echo '```'
    echo ""
    echo "## [FLOW] Phase Pipeline"
    echo ""
    if [[ $PHASE_COUNT -gt 0 ]]; then
        echo '_如果项目定义了 \`phases\`，按顺序展示执行流水线。_'
        echo ""
        echo '```mermaid'
        cat "$DOCS_DIR/phase-pipeline.mmd"
        echo '```'
    else
        echo "_No phases defined in this project._"
    fi
    echo ""
    echo "## [TODO] TODO Blocker Graph"
    echo ""
    echo "_[HIGH] 高优先级 · [MED] 中 · [LOW] 低 · 箭头表示\"完成后解锁\"_"
    echo ""
    echo '```mermaid'
    cat "$DOCS_DIR/todo-blocker.mmd"
    echo '```'
    echo ""
    echo "## [MOD] Module Inventory"
    echo ""
    echo "| Module | Components | Todos | Language | Description |"
    echo "|---|---:|---:|---|---|"
    while IFS=$'\t' read -r mi mname mdesc; do
        cn=$(component_count "$mi")
        tn=$(jq "[.modules[$mi].components[].todos // [] | length] | add // 0" "$STRUCT_FILE")
        lang=$(jq -r ".modules[$mi].language // \"any\"" "$STRUCT_FILE")
        echo "| \`${mname}\` | $cn | $tn | $lang | $mdesc |"
    done < <(iter_modules)
    echo ""
    echo "---"
    echo ""
    echo "_View this in a browser: open \`architecture.html\` in this directory._"
} > "$DOCS_DIR/ARCHITECTURE.md"
say "$DOCS_DIR/ARCHITECTURE.md"

# ---------- 5. architecture.html: 单文件交互式 SPA ----------

# 5.0 先把 JSON 数据 blob 写到临时文件，等会用 sed 插进去
DATA_BLOB=$(mktemp)
build_data_blob "$DATA_BLOB"

# 5.1 Mermaid graph 也单独保留（用 sed 替换嵌入）
MMD_GRAPH=$(mktemp)
cp "$DOCS_DIR/module-graph.mmd" "$MMD_GRAPH"
# 给 mermaid 加初始化指令
{
    echo "%%{init: {'theme':'base','themeVariables':{'primaryColor':'#fff9c4','primaryBorderColor':'#f57f17'}}}%%"
    cat "$MMD_GRAPH"
} > "${MMD_GRAPH}.tmp"
mv "${MMD_GRAPH}.tmp" "$MMD_GRAPH"

# 5.2 generation timestamp（保持确定性：使用 STRUCT_FILE 的 mtime）
GEN_TS=$(stat -c %Y "$STRUCT_FILE" 2>/dev/null || date +%s)
GEN_DATE=$(date -u -d "@$GEN_TS" +"%Y-%m-%d %H:%M:%S UTC" 2>/dev/null || date -u +"%Y-%m-%d %H:%M:%S UTC")

# 5.3 escape JSON for embedding inside <script type="application/json">
# 仅做最小防御：关闭 </script>。jq 已经保证合法 JSON。
EMBED_JSON=$(sed 's|</script>|</scr"+"ipt>|g' "$DATA_BLOB")

# 5.4 写最终的 HTML
HTML_OUT="$DOCS_DIR/architecture.html"

# 把 mermaid graph 也 escape 一下嵌入
EMBED_MMD=$(sed 's|</script>|</scr"+"ipt>|g' "$MMD_GRAPH")

# 主 HTML 通过 stage 文件 + sed 注入。
STAGE=$(mktemp)

cat > "$STAGE" <<'HTML_TOP'
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>Architecture Overview</title>
<script id="project-data" type="application/json">
HTML_TOP

# 注入 JSON blob
cat "$DATA_BLOB" | sed 's|</script>|</scr"+"ipt>|g' >> "$STAGE"

cat >> "$STAGE" <<'HTML_DATA_END'
</script>
<style>
:root {
  --bg:        #fafafa;
  --bg-elev:   #ffffff;
  --bg-sunk:   #f1f3f5;
  --border:    #e1e4e8;
  --text:      #1f2328;
  --text-dim:  #57606a;
  --accent:    #1976d2;
  --accent-bg: #e3f2fd;
  --warn:      #f57f17;
  --good:      #2e7d32;
  --bad:       #c62828;
  --shadow:    0 1px 3px rgba(0,0,0,.08), 0 1px 2px rgba(0,0,0,.04);
  --mono:      ui-monospace, SFMono-Regular, "SF Mono", Menlo, Monaco, Consolas, monospace;
  --sans:      -apple-system, BlinkMacSystemFont, "Segoe UI", Helvetica, Arial, sans-serif;
}
body.dark {
  --bg:        #0d1117;
  --bg-elev:   #161b22;
  --bg-sunk:   #010409;
  --border:    #30363d;
  --text:      #e6edf3;
  --text-dim:  #8b949e;
  --accent:    #58a6ff;
  --accent-bg: #1f6feb33;
  --warn:      #d29922;
  --good:      #3fb950;
  --bad:       #f85149;
  --shadow:    0 1px 3px rgba(0,0,0,.5), 0 1px 2px rgba(0,0,0,.4);
}
* { box-sizing: border-box; }
html, body {
  margin: 0; padding: 0;
  background: var(--bg);
  color: var(--text);
  font-family: var(--sans);
  font-size: 14px;
  line-height: 1.5;
  transition: background .15s, color .15s;
}
header.app-header {
  display: flex; align-items: center; justify-content: space-between;
  padding: 14px 24px;
  background: var(--bg-elev);
  border-bottom: 1px solid var(--border);
  box-shadow: var(--shadow);
  position: sticky; top: 0; z-index: 50;
}
header.app-header h1 {
  margin: 0; font-size: 18px; font-weight: 600;
}
header.app-header h1 .glyph { color: var(--accent); margin-right: 8px; }
header.app-header .meta { color: var(--text-dim); font-size: 12px; margin-left: 12px; }
.toggle-btn {
  background: var(--bg-sunk);
  color: var(--text);
  border: 1px solid var(--border);
  border-radius: 6px;
  padding: 6px 12px;
  font: inherit;
  cursor: pointer;
  transition: background .15s, border-color .15s;
}
.toggle-btn:hover { background: var(--accent-bg); border-color: var(--accent); }
.stats-bar {
  display: flex; gap: 0; flex-wrap: wrap;
  background: var(--bg-elev);
  border-bottom: 1px solid var(--border);
  padding: 0;
}
.stats-bar .stat {
  flex: 1; min-width: 130px;
  padding: 14px 20px;
  border-right: 1px solid var(--border);
}
.stats-bar .stat:last-child { border-right: 0; }
.stats-bar .stat .label {
  font-size: 11px; text-transform: uppercase; letter-spacing: .05em;
  color: var(--text-dim);
}
.stats-bar .stat .value {
  font-family: var(--mono); font-size: 22px; font-weight: 600;
  color: var(--text);
  margin-top: 4px;
}
.stats-bar .stat .sub { font-size: 11px; color: var(--text-dim); margin-top: 2px; }
.progress-bar {
  height: 6px; background: var(--bg-sunk); border-radius: 3px; overflow: hidden;
  margin-top: 6px;
}
.progress-bar > .fill {
  height: 100%; background: var(--good); transition: width .3s;
}
.layout {
  display: grid;
  grid-template-columns: 280px 1fr 340px;
  grid-template-rows: 1fr auto;
  grid-template-areas:
    "left center right"
    "bottom bottom bottom";
  height: calc(100vh - 134px);  /* header + stats */
  min-height: 500px;
}
.panel-left  { grid-area: left;   border-right: 1px solid var(--border); background: var(--bg-elev); overflow: hidden; display: flex; flex-direction: column; }
.panel-center{ grid-area: center; background: var(--bg);        overflow: auto; padding: 16px; }
.panel-right { grid-area: right;  border-left:  1px solid var(--border); background: var(--bg-elev); overflow: auto; padding: 16px; }
.panel-bottom{ grid-area: bottom; border-top:   1px solid var(--border); background: var(--bg-elev); padding: 12px 24px; max-height: 220px; overflow: auto; }

@media (max-width: 1100px) {
  .layout {
    grid-template-columns: 240px 1fr;
    grid-template-rows: 1fr auto auto;
    grid-template-areas:
      "left center"
      "right right"
      "bottom bottom";
    height: auto;
  }
  .panel-left, .panel-center, .panel-right { height: auto; min-height: 300px; }
}

.search-box {
  padding: 10px 12px;
  border-bottom: 1px solid var(--border);
}
.search-box input {
  width: 100%; padding: 7px 10px;
  background: var(--bg); color: var(--text);
  border: 1px solid var(--border); border-radius: 6px;
  font: inherit;
}
.search-box input:focus { outline: none; border-color: var(--accent); }
.filter-row {
  display: flex; flex-wrap: wrap; gap: 4px;
  padding: 8px 12px; border-bottom: 1px solid var(--border);
}
.filter-btn {
  padding: 3px 8px;
  background: var(--bg-sunk); color: var(--text-dim);
  border: 1px solid var(--border); border-radius: 12px;
  font-size: 11px; cursor: pointer;
  transition: all .12s;
}
.filter-btn:hover { color: var(--text); border-color: var(--accent); }
.filter-btn.active {
  background: var(--accent-bg); color: var(--accent); border-color: var(--accent);
}
.component-list {
  flex: 1; overflow: auto; padding: 4px 0;
}
.component-item {
  padding: 7px 12px;
  cursor: pointer;
  border-left: 3px solid transparent;
  font-size: 13px;
  transition: background .1s;
}
.component-item:hover { background: var(--bg-sunk); }
.component-item.active {
  background: var(--accent-bg);
  border-left-color: var(--accent);
}
.component-item .cname { font-weight: 500; }
.component-item .cmodule { color: var(--text-dim); font-size: 11px; margin-left: 4px; }
.component-item.optional .cname::after {
  content: " opt";
  font-size: 10px; color: var(--text-dim);
  background: var(--bg-sunk); padding: 0 4px; border-radius: 3px; margin-left: 4px;
}
.component-item.highlight { background: var(--accent-bg); }

.mermaid-host {
  background: var(--bg-elev);
  border: 1px solid var(--border);
  border-radius: 8px;
  padding: 16px;
  box-shadow: var(--shadow);
  overflow: auto;
  min-height: 400px;
}
.mermaid-host .mermaid { background: transparent; }

.detail-empty {
  color: var(--text-dim);
  font-style: italic;
  padding: 24px 12px;
  text-align: center;
}
.detail-name {
  font-family: var(--mono);
  font-size: 16px;
  font-weight: 600;
  margin: 0 0 4px 0;
  color: var(--accent);
}
.detail-meta {
  font-size: 12px;
  color: var(--text-dim);
  margin-bottom: 12px;
}
.detail-section { margin-top: 14px; }
.detail-section h4 {
  margin: 0 0 6px 0;
  font-size: 11px; text-transform: uppercase; letter-spacing: .05em;
  color: var(--text-dim);
}
.tag-list { display: flex; flex-wrap: wrap; gap: 4px; }
.tag {
  display: inline-block;
  padding: 2px 7px;
  background: var(--bg-sunk);
  border: 1px solid var(--border);
  border-radius: 10px;
  font-family: var(--mono);
  font-size: 11px;
  color: var(--text);
  cursor: pointer;
  transition: all .12s;
}
.tag:hover { background: var(--accent-bg); border-color: var(--accent); color: var(--accent); }
.tag.module { background: var(--accent-bg); border-color: var(--accent); color: var(--accent); }
.tag.status-done       { background: #2e7d3220; border-color: var(--good); color: var(--good); }
.tag.status-pending    { background: var(--bg-sunk); border-color: var(--border); color: var(--text-dim); }
.tag.status-in_progress{ background: #f57f1720; border-color: var(--warn); color: var(--warn); }
.tag.priority-high   { border-color: var(--bad); color: var(--bad); }
.tag.priority-medium { border-color: var(--warn); color: var(--warn); }
.tag.priority-low    { border-color: var(--good); color: var(--good); }

.todo-row {
  padding: 6px 8px;
  background: var(--bg-sunk);
  border-radius: 4px;
  margin-bottom: 4px;
  font-size: 12px;
}
.todo-row .todo-id { font-family: var(--mono); color: var(--text-dim); }
.todo-row .todo-task { display: block; margin-top: 2px; }
.todo-row .todo-tags { margin-top: 4px; display: flex; gap: 4px; flex-wrap: wrap; }

.wave-timeline {
  display: flex; gap: 10px; overflow-x: auto;
  padding-bottom: 4px;
}
.wave-card {
  flex: 0 0 220px;
  background: var(--bg-sunk);
  border: 1px solid var(--border);
  border-radius: 6px;
  padding: 10px 12px;
}
.wave-card.current { border-color: var(--accent); background: var(--accent-bg); }
.wave-card .wave-title {
  font-weight: 600; font-size: 13px;
  display: flex; justify-content: space-between; align-items: center;
}
.wave-card .wave-count {
  font-family: var(--mono); font-size: 11px; color: var(--text-dim);
}
.wave-card .wave-todos {
  margin-top: 6px;
  font-size: 11px;
  color: var(--text-dim);
  display: flex; flex-wrap: wrap; gap: 3px;
}
.wave-card .wave-todos .tag { font-size: 10px; padding: 1px 5px; cursor: default; }

.section-title {
  font-size: 12px; text-transform: uppercase; letter-spacing: .05em;
  color: var(--text-dim); margin: 0 0 10px 0;
  font-weight: 600;
}

.empty-msg {
  color: var(--text-dim);
  font-style: italic;
  padding: 8px 0;
}

.diagram-toolbar {
  display: flex; justify-content: space-between; align-items: center;
  margin-bottom: 8px;
}
.diagram-toolbar .legend {
  display: flex; gap: 12px; font-size: 11px; color: var(--text-dim);
}
.diagram-toolbar .legend .dot {
  display: inline-block; width: 10px; height: 10px; border-radius: 50%;
  vertical-align: middle; margin-right: 4px;
}

@media print {
  header.app-header, .stats-bar, .panel-left, .panel-right, .panel-bottom { display: none; }
  .layout {
    display: block; height: auto;
  }
  .panel-center {
    border: 0; padding: 0;
  }
  .mermaid-host { box-shadow: none; border: 0; }
  body { background: white; color: black; }
}
</style>
</head>
<body>

<header class="app-header">
  <div>
    <h1><span class="glyph">[ARCH]</span>Architecture Overview</h1>
    <span class="meta">Auto-generated from <code id="struct-src"></code> &middot; <span id="gen-ts"></span></span>
  </div>
  <div>
    <button class="toggle-btn" id="dark-toggle" title="Toggle dark mode">[DARK] Dark mode</button>
  </div>
</header>

<section class="stats-bar" id="stats-bar">
  <!-- filled by JS -->
</section>

<main class="layout">

  <aside class="panel-left">
    <div class="search-box">
      <input type="search" id="search-input" placeholder="Search components..." autocomplete="off">
    </div>
    <div class="filter-row" id="filter-row">
      <button class="filter-btn active" data-filter="all">all</button>
      <button class="filter-btn" data-filter="core">core</button>
      <button class="filter-btn" data-filter="optional">optional</button>
      <button class="filter-btn" data-filter="pending">has-pending</button>
      <button class="filter-btn" data-filter="done">has-done</button>
    </div>
    <div class="component-list" id="component-list">
      <!-- filled by JS -->
    </div>
  </aside>

  <section class="panel-center">
    <div class="diagram-toolbar">
      <div class="section-title">Module / Component Graph (click a node)</div>
      <div class="legend">
        <span><span class="dot" style="background:#e1f5ff;border:1px solid #01579b"></span>module</span>
        <span><span class="dot" style="background:#fff9c4;border:1px solid #f57f17"></span>component</span>
        <span><span class="dot" style="background:#f5f5f5;border:1px dashed #9e9e9e"></span>optional</span>
      </div>
    </div>
    <div class="mermaid-host">
      <div class="mermaid" id="graph-mermaid">
HTML_DATA_END

# 注入 Mermaid graph
cat "$MMD_GRAPH" | sed 's|</script>|</scr"+"ipt>|g' >> "$STAGE"

cat >> "$STAGE" <<'HTML_AFTER_GRAPH'
      </div>
    </div>
  </section>

  <aside class="panel-right" id="detail-panel">
    <div class="detail-empty">Click a component (in the graph or the list) to see details.</div>
  </aside>

  <section class="panel-bottom">
    <div class="section-title">Wave Timeline (parallel-ready todo waves)</div>
    <div class="wave-timeline" id="wave-timeline">
      <!-- filled by JS -->
    </div>
  </section>

</main>

<script src="https://cdn.jsdelivr.net/npm/mermaid@10/dist/mermaid.min.js"></script>
<script>
// ---------- 全局状态 ----------
const PROJECT = JSON.parse(document.getElementById('project-data').textContent);
const STATE = {
  search: '',
  filter: 'all',
  selected: null,
  dark: localStorage.getItem('archviz:dark') === '1',
};

// ---------- header 元数据 ----------
document.getElementById('struct-src').textContent = 'struct.json';
document.getElementById('gen-ts').textContent = 'generated ' + '__GEN_DATE__';

// ---------- 暗色模式 ----------
function applyTheme() {
  document.body.classList.toggle('dark', STATE.dark);
  document.getElementById('dark-toggle').textContent = STATE.dark ? '[LIGHT] Light mode' : '[DARK] Dark mode';
}
applyTheme();
document.getElementById('dark-toggle').addEventListener('click', () => {
  STATE.dark = !STATE.dark;
  localStorage.setItem('archviz:dark', STATE.dark ? '1' : '0');
  applyTheme();
});

// ---------- 统计面板 ----------
function renderStats() {
  const s = PROJECT.stats || {};
  const pct = s.todo_count > 0 ? Math.round(s.todo_done * 100 / s.todo_count) : 0;
  const html = `
    <div class="stat"><div class="label">Modules</div><div class="value">${s.module_count || 0}</div></div>
    <div class="stat"><div class="label">Components</div><div class="value">${s.component_count || 0}</div>
      <div class="sub">${s.optional_count || 0} optional</div></div>
    <div class="stat"><div class="label">TODOs</div><div class="value">${s.todo_count || 0}</div>
      <div class="sub">${s.todo_done || 0} done / ${s.todo_pending || 0} pending</div></div>
    <div class="stat"><div class="label">Blockers</div><div class="value">${s.blocker_count || 0}</div></div>
    <div class="stat"><div class="label">Phases</div><div class="value">${s.phase_count || 0}</div></div>
    <div class="stat"><div class="label">Progress</div><div class="value">${pct}%</div>
      <div class="progress-bar"><div class="fill" style="width:${pct}%"></div></div></div>
  `;
  document.getElementById('stats-bar').innerHTML = html;
}
renderStats();

// ---------- 组件列表 (left panel) ----------
function findComponent(name) {
  return (PROJECT.components || []).find(c => c.name === name);
}

function componentMatchesFilter(c) {
  switch (STATE.filter) {
    case 'all':      return true;
    case 'core':     return !c.optional;
    case 'optional': return !!c.optional;
    case 'pending':  return (c.todos || []).some(t => t.status !== 'done');
    case 'done':     return (c.todos || []).some(t => t.status === 'done');
    default:         return true;
  }
}

function componentMatchesSearch(c) {
  if (!STATE.search) return true;
  const q = STATE.search.toLowerCase();
  if (c.name.toLowerCase().includes(q)) return true;
  if ((c.description || '').toLowerCase().includes(q)) return true;
  if ((c.module || '').toLowerCase().includes(q)) return true;
  if ((c.exports || []).some(x => x.toLowerCase().includes(q))) return true;
  return false;
}

function renderComponentList() {
  const list = document.getElementById('component-list');
  const comps = (PROJECT.components || [])
    .filter(c => componentMatchesFilter(c) && componentMatchesSearch(c))
    .sort((a, b) => a.name.localeCompare(b.name));
  if (comps.length === 0) {
    list.innerHTML = '<div class="empty-msg" style="padding:12px;">No components match.</div>';
    return;
  }
  list.innerHTML = comps.map(c => {
    const isOpt = c.optional ? ' optional' : '';
    const isActive = STATE.selected === c.name ? ' active' : '';
    return `<div class="component-item${isOpt}${isActive}" data-name="${c.name}">
      <span class="cname">${c.name}</span><span class="cmodule">${c.module || ''}</span>
    </div>`;
  }).join('');
  list.querySelectorAll('.component-item').forEach(el => {
    el.addEventListener('click', () => selectComponent(el.dataset.name));
  });
}

// ---------- 详情面板 (right panel) ----------
function statusClass(s) {
  return 'status-' + (s || 'pending');
}

function renderDetail(name) {
  const panel = document.getElementById('detail-panel');
  const c = findComponent(name);
  if (!c) {
    panel.innerHTML = '<div class="detail-empty">Component not found: ' + escapeHtml(name) + '</div>';
    return;
  }
  const exports = (c.exports || []).map(x => `<span class="tag">${escapeHtml(x)}</span>`).join('') || '<span class="empty-msg">none</span>';
  const imports = (c.imports || []).map(x => {
    const exists = findComponent(x) ? '' : ' style="opacity:.6"';
    return `<span class="tag" data-name="${escapeHtml(x)}"${exists}>${escapeHtml(x)}</span>`;
  }).join('') || '<span class="empty-msg">none</span>';
  const todos = (c.todos || []);
  const todosHtml = todos.length === 0
    ? '<div class="empty-msg">No todos for this component.</div>'
    : todos.map(t => `
      <div class="todo-row">
        <span class="todo-id">${escapeHtml(t.id)}</span>
        <span class="todo-task">${escapeHtml(t.task)}</span>
        <div class="todo-tags">
          <span class="tag ${statusClass(t.status)}">${escapeHtml(t.status || 'pending')}</span>
          <span class="tag priority-${escapeHtml(t.priority || 'medium')}">${escapeHtml(t.priority || 'medium')}</span>
          ${(t.blocks || []).map(b => `<span class="tag">blocks: ${escapeHtml(b)}</span>`).join('')}
        </div>
      </div>
    `).join('');

  panel.innerHTML = `
    <div class="detail-name">${escapeHtml(c.name)}</div>
    <div class="detail-meta">
      module: <span class="tag module" data-name="${escapeHtml(c.module)}">${escapeHtml(c.module || '?')}</span>
      ${c.optional ? ' &middot; <em>optional</em>' : ''}
    </div>
    <div class="detail-section">
      <h4>Description</h4>
      <div>${escapeHtml(c.description || '')}</div>
    </div>
    <div class="detail-section">
      <h4>Exports (${(c.exports || []).length})</h4>
      <div class="tag-list">${exports}</div>
    </div>
    <div class="detail-section">
      <h4>Imports (${(c.imports || []).length}) &mdash; click to navigate</h4>
      <div class="tag-list">${imports}</div>
    </div>
    <div class="detail-section">
      <h4>TODOs (${todos.length})</h4>
      ${todosHtml}
    </div>
  `;

  // 绑定跳转
  panel.querySelectorAll('.tag[data-name]').forEach(el => {
    el.addEventListener('click', () => {
      const target = el.dataset.name;
      if (findComponent(target)) selectComponent(target);
    });
  });
}

function selectComponent(name) {
  STATE.selected = name;
  renderDetail(name);
  // 高亮左侧
  document.querySelectorAll('.component-item').forEach(el => {
    el.classList.toggle('active', el.dataset.name === name);
  });
  // 滚动左侧到该项
  const item = document.querySelector('.component-item[data-name="' + cssEscape(name) + '"]');
  if (item) item.scrollIntoView({ block: 'nearest', behavior: 'smooth' });
}

// ---------- 工具 ----------
function escapeHtml(s) {
  return String(s == null ? '' : s)
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&#39;');
}
function cssEscape(s) {
  return String(s).replace(/["\\]/g, '\\$&');
}

// ---------- Wave Timeline ----------
function computeWaves() {
  // 复用 _lib.sh compute_waves 不可能（前端），前端版：按 blocker DAG 计算 wave
  const todos = PROJECT.todos || [];
  const blockedBy = {};
  const allIds = new Set(todos.map(t => t.id));
  todos.forEach(t => {
    blockedBy[t.id] = (t.blocks || []).filter(b => allIds.has(b));
  });
  const depth = {};
  function d(id, seen) {
    if (depth[id] != null) return depth[id];
    if (seen.has(id)) return 1;  // 防环
    seen.add(id);
    const ps = blockedBy[id] || [];
    if (ps.length === 0) { depth[id] = 1; return 1; }
    const m = Math.max(...ps.map(p => d(p, seen)));
    depth[id] = m + 1;
    return depth[id];
  }
  todos.forEach(t => d(t.id, new Set()));
  const byWave = {};
  Object.keys(depth).forEach(id => {
    const w = depth[id];
    (byWave[w] = byWave[w] || []).push(id);
  });
  // 稳定排序
  Object.keys(byWave).forEach(w => byWave[w].sort());
  return byWave;
}

function renderWaves() {
  const waves = computeWaves();
  const waveNums = Object.keys(waves).map(Number).sort((a,b) => a-b);
  const maxWave = waveNums.length;
  const container = document.getElementById('wave-timeline');
  if (waveNums.length === 0) {
    container.innerHTML = '<div class="empty-msg">No todos defined.</div>';
    return;
  }
  container.innerHTML = waveNums.map(w => {
    const ids = waves[w];
    const done = ids.filter(id => {
      const t = (PROJECT.todos || []).find(x => x.id === id);
      return t && t.status === 'done';
    }).length;
    const isCur = w === 1 ? ' current' : '';
    return `<div class="wave-card${isCur}">
      <div class="wave-title">
        <span>Wave ${w}${w === 1 ? ' (current)' : ''}</span>
        <span class="wave-count">${done}/${ids.length}</span>
      </div>
      <div class="progress-bar"><div class="fill" style="width:${ids.length ? done * 100 / ids.length : 0}%"></div></div>
      <div class="wave-todos">
        ${ids.slice(0, 12).map(id => {
          const t = (PROJECT.todos || []).find(x => x.id === id);
          const p = t && t.priority ? t.priority : 'medium';
          return `<span class="tag priority-${p}" title="${escapeHtml(id)}">${escapeHtml(id)}</span>`;
        }).join('')}
        ${ids.length > 12 ? `<span class="tag">+${ids.length - 12} more</span>` : ''}
      </div>
    </div>`;
  }).join('');
}
renderWaves();

// ---------- 搜索 + 过滤器 ----------
document.getElementById('search-input').addEventListener('input', e => {
  STATE.search = e.target.value.trim();
  renderComponentList();
});
document.querySelectorAll('.filter-btn').forEach(btn => {
  btn.addEventListener('click', () => {
    document.querySelectorAll('.filter-btn').forEach(b => b.classList.remove('active'));
    btn.classList.add('active');
    STATE.filter = btn.dataset.filter;
    renderComponentList();
  });
});

// ---------- Mermaid 初始化（带回调）----------
let mermaidReady = false;
function callOnClick(nodeId) {
  // Mermaid click 回调：nodeId 即组件 PascalCase 名
  selectComponent(nodeId);
}
function callModuleClick(nodeId) {
  // 点击模块：在左侧筛选到该模块的所有组件
  STATE.search = nodeId;
  document.getElementById('search-input').value = nodeId;
  renderComponentList();
}

if (typeof mermaid !== 'undefined') {
  mermaid.initialize({
    startOnLoad: true,
    theme: STATE.dark ? 'dark' : 'default',
    securityLevel: 'loose',
    callback: function(id) { mermaidReady = true; }
  });
}

// ---------- 初始 render ----------
renderComponentList();
</script>
</body>
</html>
HTML_AFTER_GRAPH

# 5.5 替换时间戳占位符。BSD sed 和 GNU sed 的 -i 参数不兼容，
# 用临时文件保持跨平台。
STAGE_TS=$(mktemp)
sed "s|__GEN_DATE__|${GEN_DATE}|g" "$STAGE" > "$STAGE_TS"
mv "$STAGE_TS" "$STAGE"

# 5.6 写出最终文件
cp "$STAGE" "$HTML_OUT"
say "$HTML_OUT"

# 5.7 deps cache: 让 incremental build 工作
mark_generated "$HTML_OUT" "$STRUCT_FILE" "$DOCS_DIR/module-graph.mmd"

# 清理临时文件
rm -f "$DATA_BLOB" "$MMD_GRAPH" "$STAGE"
