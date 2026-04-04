#!/usr/bin/env bash
# Skill Update Team — 統一入口
# sut scan | report | check | approve | reject | defer | rollback
set -euo pipefail

SUT_HOME="$(cd "$(dirname "$0")" && pwd)"
STATE_DIR="${SUT_HOME}/state"
LOGS_DIR="${SUT_HOME}/logs"
CLAUDE="${CLAUDE_BIN:-$(command -v claude 2>/dev/null || echo "${HOME}/.local/bin/claude")}"

TODAY=$(date +%Y-%m-%d)
SEVEN_DAYS_AGO=$(date -v-7d +%Y-%m-%d 2>/dev/null || date -d '7 days ago' +%Y-%m-%d)
THIRTY_DAYS_AGO=$(date -v-30d +%Y-%m-%d 2>/dev/null || date -d '30 days ago' +%Y-%m-%d)
LOG_FILE="${LOGS_DIR}/run-${TODAY}.log"

mkdir -p "$STATE_DIR" "${SUT_HOME}/snapshots" "$LOGS_DIR"
log() { echo "[$(date '+%H:%M:%S')] $*" | tee -a "$LOG_FILE"; }

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# scan
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
cmd_scan() {
  log "=== Skill Update Team 掃描開始 ==="

  local SOURCES_BLOCK="" SCORERS_BLOCK="" ACTIONS_BLOCK=""
  local SC=0 SCC=0 AC=0

  for f in "$SUT_HOME"/sources/*.yaml; do
    [[ -f "$f" ]] && grep -q "enabled: true" "$f" && { SOURCES_BLOCK+=$'\n'"--- Source: $(basename "$f" .yaml) ---"$'\n'"$(cat "$f")"$'\n'; ((SC++)); }
  done
  for f in "$SUT_HOME"/scorers/*.yaml; do
    [[ -f "$f" ]] && grep -q "enabled: true" "$f" && { SCORERS_BLOCK+=$'\n'"--- Scorer: $(basename "$f" .yaml) ---"$'\n'"$(cat "$f")"$'\n'; ((SCC++)); }
  done
  for f in "$SUT_HOME"/actions/*.yaml; do
    [[ -f "$f" ]] && grep -q "enabled: true" "$f" && { ACTIONS_BLOCK+=$'\n'"--- Action: $(basename "$f" .yaml) ---"$'\n'"$(cat "$f")"$'\n'; ((AC++)); }
  done
  log "Plugins: ${SC} sources, ${SCC} scorers, ${AC} actions"

  local INSTALLED_MCPS
  INSTALLED_MCPS=$("$CLAUDE" mcp list 2>/dev/null | grep "✓ Connected" | sed 's/:.*//' | tr -s ' ' | sed 's/^ //' || echo "none")

  local PREF_HISTORY="[]"
  [[ -f "${STATE_DIR}/preferences.jsonl" ]] && PREF_HISTORY=$(tail -20 "${STATE_DIR}/preferences.jsonl" | jq -s '.' 2>/dev/null || echo "[]")

  local PROMPT
  PROMPT=$(cat "${SUT_HOME}/prompts/research.md")
  PROMPT="${PROMPT//\{\{INSTALLED_MCPS\}\}/$INSTALLED_MCPS}"
  PROMPT="${PROMPT//\{\{PREFERENCE_HISTORY\}\}/$PREF_HISTORY}"
  PROMPT="${PROMPT//\{\{SOURCES\}\}/$SOURCES_BLOCK}"
  PROMPT="${PROMPT//\{\{SCORERS\}\}/$SCORERS_BLOCK}"
  PROMPT="${PROMPT//\{\{ACTIONS\}\}/$ACTIONS_BLOCK}"
  PROMPT="${PROMPT//\{\{TODAY\}\}/$TODAY}"
  PROMPT="${PROMPT//\{\{7_DAYS_AGO\}\}/$SEVEN_DAYS_AGO}"
  PROMPT="${PROMPT//\{\{30_DAYS_AGO\}\}/$THIRTY_DAYS_AGO}"

  log "Research Agent 啟動..."
  local RESULT_FILE="${STATE_DIR}/research-${TODAY}.json"

  "$CLAUDE" -p \
    --model sonnet \
    --output-format json \
    --max-budget-usd 0.50 \
    --allowedTools "mcp__firecrawl__firecrawl_search,mcp__firecrawl__firecrawl_scrape,mcp__claude_ai_Context7__resolve-library-id,mcp__claude_ai_Context7__query-docs,WebSearch,WebFetch" \
    "$PROMPT" \
    2>>"$LOG_FILE" | jq -r '.result // .content // .' > "$RESULT_FILE"

  [[ ! -s "$RESULT_FILE" ]] && { log "ERROR: 無結果"; exit 1; }

  generate_report "$RESULT_FILE"
  echo ""
  echo "✅ 掃描完成"
  echo ""

  # 互動推薦：只顯示高分項目，問使用者要不要裝
  show_recommendations "$RESULT_FILE"

  echo ""
  echo "   sut report          看完整報告"
  echo "   sut check <id>      安全檢查"
  echo "   sut approve <id>    安裝"
}

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# report
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
cmd_report() {
  local R
  R=$(ls -t "$STATE_DIR"/report-*.md 2>/dev/null | head -1)
  if [[ -n "$R" ]]; then
    cat "$R"
  else
    echo "還沒有報告。先執行: sut scan"
  fi
}

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# check — 安全審查
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
cmd_check() {
  local FID="$1"
  local F; F=$(find_finding "$FID")
  [[ "$F" == "NOT_FOUND" ]] && { echo "找不到 $FID"; exit 1; }

  local NAME URL TYPE ICMD
  NAME=$(echo "$F" | jq -r '.name')
  URL=$(echo "$F" | jq -r '.url')
  TYPE=$(echo "$F" | jq -r '.type')
  ICMD=$(echo "$F" | jq -r '.install_command // "N/A"')

  echo "🔒 安全檢查: $NAME"
  echo "   $URL"
  echo ""

  local SEC; SEC=$(cat "$SUT_HOME/security/checks.yaml")
  local AP; AP=$(cat "$SUT_HOME/prompts/security-audit.md")
  AP="${AP//\{\{NAME\}\}/$NAME}"
  AP="${AP//\{\{URL\}\}/$URL}"
  AP="${AP//\{\{TYPE\}\}/$TYPE}"
  AP="${AP//\{\{INSTALL_COMMAND\}\}/$ICMD}"
  AP="${AP//\{\{SECURITY_CHECKS\}\}/$SEC}"
  AP="${AP//\{\{TODAY\}\}/$TODAY}"

  local AF="${STATE_DIR}/audit-${FID}-${TODAY}.json"

  "$CLAUDE" -p \
    --model sonnet \
    --output-format json \
    --max-budget-usd 0.20 \
    --allowedTools "mcp__firecrawl__firecrawl_scrape,mcp__firecrawl__firecrawl_search,WebFetch" \
    "$AP" \
    2>>"$LOG_FILE" | jq -r '.result // .content // .' > "$AF"

  local V; V=$(jq -r '.overall_verdict // "UNKNOWN"' "$AF" 2>/dev/null || echo "UNKNOWN")

  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  case "$V" in
    SAFE)     echo "✅ SAFE — 可以安裝" ;;
    CAUTION)  echo "⚠️  CAUTION — 有風險項目" ;;
    BLOCKED)  echo "🚫 BLOCKED — 不建議安裝" ;;
    *)        echo "❓ 無法判定，請手動看 $AF" ;;
  esac
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo ""
  jq -r '.checks[]? | "\(if .result == "PASS" then "  ✅" elif .result == "WARN" then "  ⚠️ " else "  ❌" end) \(.id): \(.details)"' "$AF" 2>/dev/null || true
  echo ""
  jq -r '"💡 " + .risk_summary' "$AF" 2>/dev/null || true
}

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# approve — check → snapshot → install → smoke
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
cmd_approve() {
  local FID="$1" REASON="${2:-}"
  local F; F=$(find_finding "$FID")
  [[ "$F" == "NOT_FOUND" ]] && { echo "找不到 $FID"; exit 1; }

  local NAME ICMD
  NAME=$(echo "$F" | jq -r '.name')
  ICMD=$(echo "$F" | jq -r '.install_command // "N/A"')

  # 安全檢查（沒做過就先做）
  local AF="${STATE_DIR}/audit-${FID}-${TODAY}.json"
  if [[ ! -f "$AF" ]]; then
    echo "先跑安全檢查..."
    cmd_check "$FID"
    echo ""
  fi

  local V="UNKNOWN"
  [[ -f "$AF" ]] && V=$(jq -r '.overall_verdict // "UNKNOWN"' "$AF" 2>/dev/null || echo "UNKNOWN")

  if [[ "$V" == "BLOCKED" ]]; then
    echo "🚫 安全審查 BLOCKED，拒絕安裝。"
    echo "   強制安裝: $ICMD"
    record_pref "$FID" "$NAME" "blocked" "security-blocked" "$REASON"
    return 1
  fi
  if [[ "$V" == "CAUTION" ]]; then
    echo "⚠️  有風險，繼續? (y/N)"
    read -r YN
    [[ "$YN" != "y" && "$YN" != "Y" ]] && { echo "取消"; return 0; }
  fi

  # Snapshot
  local SD="${SUT_HOME}/snapshots/snap-$(date +%Y%m%d-%H%M%S)"
  mkdir -p "$SD"
  cp -f ~/.claude/settings.json "$SD/" 2>/dev/null || true
  cp -f ~/.claude/settings.local.json "$SD/" 2>/dev/null || true
  "$CLAUDE" mcp list > "$SD/mcp-list.txt" 2>/dev/null || true
  echo "$SD" > "${STATE_DIR}/last-snapshot.txt"
  echo "📸 Snapshot: $SD"

  # Install
  echo "🔧 $ICMD"
  if eval "$ICMD" 2>&1; then
    if "$CLAUDE" mcp list 2>/dev/null | grep -q "✓ Connected"; then
      echo "✅ 安裝成功"
      record_pref "$FID" "$NAME" "approve" "installed" "$REASON"
    else
      echo "⚠️  安裝完成，健康檢查異常"
      record_pref "$FID" "$NAME" "approve" "installed-warning" "$REASON"
    fi
  else
    echo "❌ 失敗，rollback..."
    cmd_rollback
    record_pref "$FID" "$NAME" "approve" "failed" "$REASON"
  fi
}

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# reject / defer / rollback
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
cmd_reject() {
  local FID="$1" REASON="${2:-}"
  local N; N=$(find_finding "$FID" | jq -r '.name // "?"' 2>/dev/null || echo "?")
  record_pref "$FID" "$N" "reject" "recorded" "$REASON"
  echo "✅ reject: $N"
}

cmd_defer() {
  local FID="$1" REASON="${2:-}"
  local N; N=$(find_finding "$FID" | jq -r '.name // "?"' 2>/dev/null || echo "?")
  record_pref "$FID" "$N" "defer" "recorded" "$REASON"
  echo "✅ defer: $N"
}

cmd_rollback() {
  local LSF="${STATE_DIR}/last-snapshot.txt"
  [[ ! -f "$LSF" ]] && { echo "沒有 snapshot"; exit 1; }
  local SD; SD=$(cat "$LSF")
  [[ ! -d "$SD" ]] && { echo "Snapshot 不在了: $SD"; exit 1; }
  cp -f "$SD/settings.json" ~/.claude/settings.json 2>/dev/null || true
  cp -f "$SD/settings.local.json" ~/.claude/settings.local.json 2>/dev/null || true
  echo "✅ Rollback 完成"
}

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# helpers
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
find_finding() {
  local ID="$1"
  local RF; RF=$(ls -t "$STATE_DIR"/research-*.json 2>/dev/null | head -1)
  [[ -z "$RF" ]] && { echo "NOT_FOUND"; return; }
  python3 -c "
import json,sys
with open('$RF') as f:
  c=f.read().strip()
if c.startswith('\`\`\`'):
  ls=c.split('\n'); o=[]; ib=False
  for l in ls:
    if l.startswith('\`\`\`') and not ib: ib=True; continue
    elif l.startswith('\`\`\`') and ib: break
    elif ib: o.append(l)
  c='\n'.join(o)
try: d=json.loads(c)
except: print('NOT_FOUND'); sys.exit()
for f in d.get('findings',[]):
  if f.get('id')=='$ID': print(json.dumps(f)); sys.exit()
print('NOT_FOUND')
" 2>/dev/null || echo "NOT_FOUND"
}

record_pref() {
  echo "{\"date\":\"$TODAY\",\"id\":\"$1\",\"name\":\"$2\",\"decision\":\"$3\",\"status\":\"$4\",\"reason\":\"$5\"}" >> "${STATE_DIR}/preferences.jsonl"
}

show_recommendations() {
  local RESULT_FILE="$1"
  RESULT_FILE="$RESULT_FILE" python3 << 'PYEOF'
import json,sys,os
rf=os.environ["RESULT_FILE"]
try:
  with open(rf) as f: c=f.read().strip()
  if c.startswith('```'):
    ls=c.split('\n'); jl=[]; ib=False
    for l in ls:
      if l.startswith('```') and not ib: ib=True; continue
      elif l.startswith('```') and ib: break
      elif ib: jl.append(l)
    c='\n'.join(jl)
  data=json.loads(c)
except: sys.exit(0)
fs=data.get('findings',[])
rec=[f for f in fs if f.get('urgency','watch') in ('critical','important')]
rec.sort(key=lambda x:x.get('scores',{}).get('total',0),reverse=True)
if not rec: print("沒有高分推薦項目。"); sys.exit(0)
em={'critical':'🔴','important':'🟡'}
print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
print(f"  📋 推薦 {len(rec)} 個工具：")
print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
for i,f in enumerate(rec,1):
  e=em.get(f.get('urgency',''),'🟡'); sc=f.get('scores',{}).get('total',0)
  print(f"\n  {i}. {e} {f.get('name','?')} (總分 {sc:.2f})")
  print(f"     {f.get('description','')}")
  feats=f.get('features',[])
  if feats:
    print("     功能：")
    for ft in feats[:3]: print(f"       • {ft}")
  wfy=f.get('why_for_you','')
  if wfy: print(f"     💡 {wfy}")
  print(f"     ID: {f.get('id','?')}")
print("\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
PYEOF
}

generate_report() {
  local RESULT_FILE="$1"
  local REPORT_FILE="${STATE_DIR}/report-${TODAY}.md"
  TODAY="$TODAY" RESULT_FILE="$RESULT_FILE" REPORT_FILE="$REPORT_FILE" python3 << 'PYEOF'
import json,sys,os
today=os.environ["TODAY"]; rf=os.environ["RESULT_FILE"]; of=os.environ["REPORT_FILE"]
try:
  with open(rf) as f: c=f.read().strip()
  if c.startswith('```'):
    ls=c.split('\n'); jl=[]; ib=False
    for l in ls:
      if l.startswith('```') and not ib: ib=True; continue
      elif l.startswith('```') and ib: break
      elif ib: jl.append(l)
    c='\n'.join(jl)
  data=json.loads(c)
except Exception as e:
  with open(of,'w') as f: f.write(f'# Skill Update Team — {today}\n\n⚠️ 解析失敗 ({e})\n')
  sys.exit(0)
findings=data.get('findings',[]); summary=data.get('summary',{}); meta=data.get('meta_discoveries',[])
em={'critical':'🔴','important':'🟡','nice_to_have':'🟢','watch':'⚪'}
r=f"# Skill Update Team — {today}\n\n"
r+=f"🔴 {summary.get('critical',0)} | 🟡 {summary.get('important',0)} | 🟢 {summary.get('nice_to_have',0)} | ⚪ {summary.get('watch',0)}\n\n"
sf=sorted(findings,key=lambda x:x.get('scores',{}).get('total',0),reverse=True)
rec=[f for f in sf if f.get('urgency','watch') in ('critical','important')]
rest=[f for f in sf if f.get('urgency','watch') not in ('critical','important')]
if rec:
  r+="## 📋 推薦安裝\n\n"
  for i,f in enumerate(rec,1):
    e=em.get(f.get('urgency','watch'),'⚪'); fid=f.get('id','?'); sc=f.get('scores',{})
    r+=f"### {i}. {e} {f.get('name','?')} — {f.get('urgency','?').upper()} (總分 {sc.get('total',0):.2f})\n\n"
    r+=f"**{f.get('description','')}**\n\n"
    r+=f"🔗 {f.get('url','')}\n"
    r+=f"⭐ {f.get('github_stars','N/A')} | 📦 {f.get('type','?')} | 最後更新 {f.get('last_commit','N/A')}\n\n"
    feats=f.get('features',[])
    if feats:
      r+="**功能：**\n"
      for ft in feats: r+=f"  - {ft}\n"
      r+="\n"
    wfy=f.get('why_for_you','')
    if wfy: r+=f"**為什麼適合你：** {wfy}\n\n"
    r+="**評分：**\n"
    for k,v in sc.items():
      if k!='total': r+=f"  - {k}: {v:.1f}\n" if isinstance(v,(int,float)) else f"  - {k}: {v}\n"
    r+=f"  - **總分: {sc.get('total',0):.2f}**\n\n"
    ol=', '.join(f.get('overlaps_with',[])) or '無'
    if ol!='無': r+=f"⚠️ 與已安裝工具重疊: {ol}\n\n"
    r+=f"👉 `sut check {fid}` → `sut approve {fid}`\n\n---\n\n"
else:
  r+="## 📋 推薦安裝\n\n沒有高分推薦。\n\n"
if rest:
  r+="## 📝 其他發現（僅供參考）\n\n"
  for f in rest:
    e=em.get(f.get('urgency','watch'),'⚪'); fid=f.get('id','?')
    r+=f"- {e} **{f.get('name','?')}** ({f.get('scores',{}).get('total',0):.2f}) — {f.get('description','')}\n"
  r+="\n"
if meta:
  r+="---\n## 🔍 Self-discovery\n\n"
  for m in meta: r+=f"- **{m.get('type','')}** {m.get('name','')} — {m.get('description','')}\n"
with open(of,'w') as o: o.write(r)
print('OK')
PYEOF
  log "報告: $REPORT_FILE"
}

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# dispatch
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
CMD="${1:-help}"; shift || true
case "$CMD" in
  scan)     cmd_scan ;;
  report)   cmd_report ;;
  check)    cmd_check "${1:?找不到 id，用法: sut check <id>}" ;;
  approve)  cmd_approve "${1:?用法: sut approve <id>}" "${2:-}" ;;
  reject)   cmd_reject "${1:?用法: sut reject <id>}" "${2:-}" ;;
  defer)    cmd_defer "${1:?用法: sut defer <id>}" "${2:-}" ;;
  rollback) cmd_rollback ;;
  *)
    echo "Skill Update Team"
    echo ""
    echo "  sut scan              掃描新工具"
    echo "  sut report            看報告"
    echo "  sut check <id>        安全檢查"
    echo "  sut approve <id>      安裝"
    echo "  sut reject <id>       拒絕"
    echo "  sut defer <id>        延後"
    echo "  sut rollback          還原上次安裝"
    ;;
esac
