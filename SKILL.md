---
name: skill-update-team
description: >
  Skill Update Team — 自動化 AI 工具研究與安裝 Agent。
  掃描 GitHub、Reddit、YouTube、Anthropic changelog，發現新的 MCP servers、
  Claude Code plugins、AI 工具，經安全檢查後推薦安裝。
  Plugin 架構：sources / scorers / actions 均可獨立擴展。
  觸發關鍵字："掃描新工具"、"有什麼新的 MCP"、"sut"、"sut scan"、"工具推薦"、"skill update"
---

# Skill Update Team (SUT)

你是 SUT Orchestrator。收到使用者指令後，調度 subagent 完成工具掃描、安全審查、安裝。

**SUT_HOME**: `~/skill-update-team`

## 指令對照

| 使用者說 | 動作 |
|---------|------|
| `sut scan` / 掃描新工具 / 有什麼新的 MCP | → 執行 **SCAN** |
| `sut report` / 看報告 | → 執行 **REPORT** |
| `sut check <id>` | → 執行 **SECURITY AUDIT** |
| `sut approve <id>` | → 執行 **APPROVE** |
| `sut reject <id>` | → 執行 **REJECT** |
| `sut defer <id>` | → 執行 **DEFER** |
| `sut rollback` | → 執行 **ROLLBACK** |
| `sut health` / 檢查工具健康 | → 執行 **HEALTH CHECK** |
| `sut trust <source/type>` | → 加入 auto-trust 清單 |
| `sut untrust <source/type>` | → 移除 auto-trust |
| `sut adjust-weights` | → 手動調整 scorer 權重 |

---

## SCAN 流程

### Step 1: 準備 context

用 Bash / Read / Glob 收集以下資訊：

```bash
# 日期
TODAY=$(date +%Y-%m-%d)
SEVEN_DAYS_AGO=$(date -v-7d +%Y-%m-%d)
THIRTY_DAYS_AGO=$(date -v-30d +%Y-%m-%d)

# 已安裝的 MCP
claude mcp list 2>/dev/null | grep "✓ Connected"

# 偏好歷史（最近 20 筆）
tail -20 ~/skill-update-team/state/preferences.jsonl 2>/dev/null

# 已安裝的 skills（列出 ~/.claude/skills/ 下的目錄）
ls ~/.claude/skills/ 2>/dev/null

# Tech stack detection
OS_VERSION=$(sw_vers -productVersion 2>/dev/null || echo "unknown")
NODE_VERSION=$(node --version 2>/dev/null || echo "not installed")
PYTHON_VERSION=$(python3 --version 2>/dev/null | awk '{print $2}' || echo "not installed")
CLAUDE_VERSION=$(claude --version 2>/dev/null || echo "unknown")
TECH_STACK="macOS $OS_VERSION / Node $NODE_VERSION / Python $PYTHON_VERSION / Claude Code $CLAUDE_VERSION"

# 偵測 Firecrawl MCP 是否可用
HAS_FIRECRAWL=$(claude mcp list 2>/dev/null | grep -c "firecrawl" || echo "0")

cat ~/skill-update-team/state/seen.json 2>/dev/null || echo "[]"
```

用 Read 讀取所有啟用的 plugin YAML：
- `~/skill-update-team/sources/*.yaml` — 只讀 `enabled: true` 的
- `~/skill-update-team/scorers/*.yaml` — 只讀 `enabled: true` 的
- `~/skill-update-team/actions/*.yaml` — 只讀 `enabled: true` 的

用 Read 讀取 `~/skill-update-team/prompts/research.md`。

### Step 2: 組裝 prompt 並 spawn Research Agent

把 research.md 中的 placeholder 替換為實際值：
- `{{INSTALLED_MCPS}}` → claude mcp list 結果
- `{{PREFERENCE_HISTORY}}` → preferences.jsonl 內容
- `{{SOURCES}}` → 所有啟用的 source YAML 內容（每個前面加 `--- Source: <name> ---`）
- `{{SCORERS}}` → 所有啟用的 scorer YAML 內容（每個前面加 `--- Scorer: <name> ---`）
- `{{ACTIONS}}` → 所有啟用的 action YAML 內容（每個前面加 `--- Action: <name> ---`）
- `{{INSTALLED_SKILLS}}` → `ls ~/.claude/skills/` 的結果
- `{{TODAY}}` / `{{7_DAYS_AGO}}` / `{{30_DAYS_AGO}}` → 日期
- `{{TECH_STACK}}` → `$TECH_STACK`
- `{{SEEN_ITEMS}}` → seen.json content
- `{{AVAILABLE_TOOLS}}` → 根據 HAS_FIRECRAWL 決定：
  - If HAS_FIRECRAWL > 0: `"firecrawl_search, firecrawl_scrape, WebSearch, WebFetch"`
  - If HAS_FIRECRAWL = 0: `"WebSearch, WebFetch（Firecrawl 不可用，請使用這兩個替代）"`

然後用 **Agent tool** spawn Research Agent：

```
Agent(
  description="SUT research scan",
  subagent_type="general-purpose",
  model="sonnet",
  prompt=<組裝好的 research prompt>
)
```

Research Agent 有權使用的工具：firecrawl_search、firecrawl_scrape、Context7、WebSearch、WebFetch。
它會回傳 JSON 格式的掃描結果。

### Step 3: 儲存結果 & 產出報告

1. 把 Research Agent 回傳的 JSON 存到 `~/skill-update-team/state/research-<TODAY>.json`
2. 更新 seen.json（合併新舊，去重）：

```bash
# 更新 seen.json（合併新舊，去重）
python3 -c "
import json
old = json.load(open('$HOME/skill-update-team/state/seen.json')) if __import__('os').path.exists('$HOME/skill-update-team/state/seen.json') else []
new_findings = json.load(open('$HOME/skill-update-team/state/research-$TODAY.json')).get('findings', [])
new_urls = [f['url'] for f in new_findings if f.get('url')]
merged = list(set(old + new_urls))
json.dump(merged, open('$HOME/skill-update-team/state/seen.json', 'w'), indent=2)
"
```

3. 從 JSON 產出 markdown 報告存到 `~/skill-update-team/state/report-<TODAY>.md`

報告格式：
```markdown
# Skill Update Team — <TODAY>

🔴 <critical 數> | 🟡 <important 數> | 🟢 <nice_to_have 數> | ⚪ <watch 數>

## 推薦安裝

### 1. 🔴/🟡 <name> — <URGENCY> (總分 <score>)
**<description>**
🔗 <url>
⭐ <stars> | 📦 <type> | 最後更新 <date>

**功能：**
- ...

**為什麼適合你：** ...

**評分：**
- relevance: ...
- ...
- **總分: ...**

→ `sut check <id>` → `sut approve <id>`

---

## 其他發現
- ⚪ **name** (score) — description

## 🧹 清理建議

以下已安裝的工具建議清理：

### 1. ❌ <name> — <reason>
<details>
移除指令: `<remove_command>`
替代品: <replaced_by>

## Self-discovery
- ...
```

### Step 4: 顯示推薦 & 清理建議

1. 只顯示 urgency = critical 或 important 的項目（精簡版），告訴使用者可以 `sut check <id>` 或 `sut approve <id>`。
2. 如果有 `cleanup_suggestions`，顯示建議清理的舊工具及原因。

確保目錄存在：`mkdir -p ~/skill-update-team/state ~/skill-update-team/snapshots ~/skill-update-team/logs`

**Auto-trust 判斷：**
讀取 `~/skill-update-team/config.yaml`（或 `config.local.yaml`）的 `auto_trust` 設定。
如果 `auto_trust.enabled` 為 true：
- 檢查 finding 的 source 是否在 `trusted_sources` 中
- 檢查是否為 `trusted_types` 中的更新類型（如 patch update）
- 檢查今日已 auto-approve 的次數是否 < `max_auto_installs_per_day`
- 如果都符合，自動執行 APPROVE 流程（仍然跑 security audit）
- 在報告中標記為 "🤖 auto-approved"

### Step 5: 推送通知（可選）

如果有 Critical urgency 的發現：
1. 檢查是否有 Slack MCP 可用：`claude mcp list 2>/dev/null | grep -c "Slack"`
2. 如果有，發送精簡通知到使用者指定的 channel

通知格式：
```
🔴 SUT 發現 <N> 項重要更新：
<finding-1-name> — <one-line-reason>
<finding-2-name> — <one-line-reason>
→ 在 Claude Code 中輸入 `sut report` 查看完整報告
```

---

## REPORT 流程

讀取最新的 `~/skill-update-team/state/report-*.md` 並顯示。

---

## SECURITY AUDIT 流程（check）

### Step 1: 找到 finding

從最新的 `~/skill-update-team/state/research-*.json` 中，找出 `id` 匹配的 finding。

### Step 2: 組裝 audit prompt

用 Read 讀取：
- `~/skill-update-team/prompts/security-audit.md`
- `~/skill-update-team/security/checks.yaml`

替換 placeholder：
- `{{NAME}}` → finding.name
- `{{URL}}` → finding.url
- `{{TYPE}}` → finding.type
- `{{INSTALL_COMMAND}}` → finding.install_command
- `{{SECURITY_CHECKS}}` → checks.yaml 內容
- `{{TODAY}}` → 今天日期

### Step 3: Spawn Security Auditor Agent

```
Agent(
  description="SUT security audit",
  subagent_type="general-purpose",
  model="sonnet",
  prompt=<組裝好的 audit prompt>
)
```

### Step 4: 儲存並顯示結果

存到 `~/skill-update-team/state/audit-<id>-<TODAY>.json`。

顯示：
- Overall verdict: SAFE / CAUTION / BLOCKED
- 每項 check 的結果
- 風險摘要

---

## APPROVE 流程

### Step 1: 安全檢查

如果 `~/skill-update-team/state/audit-<id>-<TODAY>.json` 不存在，先執行 SECURITY AUDIT。

讀取 verdict：
- **BLOCKED** → 拒絕安裝，告訴使用者原因
- **CAUTION** → 告知風險，用 AskUserQuestion 確認是否繼續
- **SAFE** → 繼續

### Step 2: Snapshot

```bash
SNAP_DIR=~/skill-update-team/snapshots/snap-$(date +%Y%m%d-%H%M%S)
mkdir -p "$SNAP_DIR"
cp ~/.claude/settings.json "$SNAP_DIR/" 2>/dev/null || true
cp ~/.claude/settings.local.json "$SNAP_DIR/" 2>/dev/null || true
claude mcp list > "$SNAP_DIR/mcp-list.txt" 2>/dev/null || true
echo "$SNAP_DIR" > ~/skill-update-team/state/last-snapshot.txt
```

### Step 3: 安裝

執行 finding 中的 `install_command`。

### Step 4: Smoke test

檢查安裝是否成功（例如 `claude mcp list` 確認 MCP 已 connected）。

### Step 5: 記錄偏好

```bash
echo '{"date":"<TODAY>","id":"<id>","name":"<name>","decision":"approve","status":"installed","action_type":"<mcp-add|npm-install|pip-install|skill-install>","install_command":"<實際執行的安裝指令>","rollback_command":"<對應 action YAML 的 rollback 指令>","snapshot_dir":"<SNAP_DIR 路徑>"}' >> ~/skill-update-team/state/preferences.jsonl
```

如果安裝失敗，自動 rollback 並記錄 status="failed"。

---

## REJECT 流程

記錄偏好並告知使用者：

```bash
echo '{"date":"<TODAY>","id":"<id>","name":"<name>","decision":"reject","reason":"<使用者給的理由>"}' >> ~/skill-update-team/state/preferences.jsonl
```

---

## DEFER 流程

同 REJECT，但 decision="defer"。

---

## ROLLBACK 流程

### Step 1: 讀取最後一筆安裝記錄

從 `~/skill-update-team/state/preferences.jsonl` 讀取最後一筆 `decision="approve"` 且 `status="installed"` 的記錄。

### Step 2: 執行 rollback

根據 `action_type` 決定 rollback 策略：
- **mcp-add**: 還原 snapshot（settings.json）
- **npm-install**: 執行記錄中的 `rollback_command`（`npm uninstall -g ...`）
- **pip-install**: 執行 `rollback_command`（`pip3 uninstall -y ...`）
- **skill-install**: 執行 `rollback_command`（`rm -rf ~/.claude/skills/...`）

### Step 3: 還原 snapshot（如有）

如果記錄中有 `snapshot_dir`，還原其中的設定檔：

```bash
SNAP_DIR=<記錄中的 snapshot_dir>
cp "$SNAP_DIR/settings.json" ~/.claude/settings.json 2>/dev/null || true
cp "$SNAP_DIR/settings.local.json" ~/.claude/settings.local.json 2>/dev/null || true
```

### Step 4: 更新記錄

把該筆記錄的 status 改為 "rolled_back"：

```bash
# 用 python3 更新 preferences.jsonl 中最後一筆 installed 記錄
python3 -c "
import json
lines = open('$HOME/skill-update-team/state/preferences.jsonl').readlines()
result = []
found = False
for line in reversed(lines):
    record = json.loads(line.strip())
    if not found and record.get('decision') == 'approve' and record.get('status') == 'installed':
        record['status'] = 'rolled_back'
        found = True
    result.insert(0, json.dumps(record, ensure_ascii=False))
open('$HOME/skill-update-team/state/preferences.jsonl', 'w').write('\n'.join(result) + '\n')
"
```

告知使用者已還原，顯示被 rollback 的工具名稱和類型。

---

## HEALTH CHECK 流程

### Step 1: 收集已安裝工具

從 `~/skill-update-team/state/preferences.jsonl` 讀取所有 `status="installed"` 的記錄，過濾出安裝超過 7 天的。

### Step 2: 組裝 prompt 並 spawn Health Check Agent

用 Read 讀取 `~/skill-update-team/prompts/post-install-check.md`，替換：
- `{{INSTALLED_ITEMS}}` → 過濾後的已安裝工具清單（JSON 格式）
- `{{TODAY}}` → 今天日期

```
Agent(
  description="SUT health check",
  subagent_type="general-purpose",
  model="sonnet",
  prompt=<組裝好的 health check prompt>
)
```

### Step 3: 顯示結果

顯示每個工具的健康狀態，特別標記 `recommendation="consider_removing"` 的項目。
建議使用者對這些項目執行 `sut rollback` 或手動移除。

---

## 重要原則

1. **Research 和 Security Audit 一定用 Agent tool + model="sonnet"** — 省錢、隔離 context
2. **主對話只做調度** — 讀 YAML、組 prompt、spawn agent、顯示結果
3. **所有狀態存在 ~/skill-update-team/state/** — JSON / JSONL 格式
4. **安裝前必過安全檢查** — 沒有例外
5. **永遠先 snapshot 再安裝** — 可以 rollback
6. **Plugin YAML 是 source of truth** — 不要 hardcode source/scorer/action 邏輯
