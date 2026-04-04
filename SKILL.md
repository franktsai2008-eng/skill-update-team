---
name: skill-update-team
description: >
  Skill Update Team — 自動化 AI 工具研究與安裝 Agent Team。
  掃描 GitHub、Reddit、YouTube、Anthropic changelog，發現新的 MCP servers、
  Claude Code plugins、AI 工具，經安全檢查後推薦安裝。
  Plugin 架構：sources / scorers / actions 均可獨立擴展。
  觸發關鍵字："掃描新工具"、"有什麼新的 MCP"、"sut"、"工具推薦"、"skill update"
---

# Skill Update Team

自動化 AI 工具研究、安全審查、安裝系統。手動觸發，不自動排程。

## 用法

所有操作透過 `sut` 指令：

```
sut scan              掃描新工具（Research → Score → 推薦高分項目並問你要不要裝）
sut report            看完整報告（含所有發現）
sut check <id>        對某個推薦執行安全審查
sut approve <id>      安裝（自動先跑安全檢查 → snapshot → install → smoke test）
sut reject <id>       拒絕（記錄偏好，影響未來評分）
sut defer <id>        延後
sut rollback          還原上次安裝
```

## 安全檢查（approve 前必過）

6 項自動檢查，定義在 `security/checks.yaml`：

| 檢查 | 嚴重度 | 說明 |
|------|--------|------|
| repo-trust | block | repo 信任度（stars、owner、LICENSE） |
| code-review | block | 掃描危險行為（curl\|sh、eval、讀取敏感目錄） |
| permissions-scope | block | 權限範圍合理性 |
| dependency-audit | warn | npm audit / CVE / typosquatting |
| data-exfil | block | 資料外洩風險 |
| freshness | warn | 維護狀態 |

判定：任何 block 項 FAIL → BLOCKED（拒絕安裝）；有 WARN → CAUTION（確認後可裝）

## Plugin 架構

```
~/skill-update-team/
├── run.sh                # 統一入口（sut 指令）
├── config.yaml
├── prompts/
│   ├── research.md       # Research Agent prompt
│   └── security-audit.md # Security Auditor prompt
├── sources/              # 🔌 資料來源 adapter
├── scorers/              # 🔌 評分維度
├── actions/              # 🔌 安裝方式 handler
├── security/             # 🔒 安全檢查規則
│   └── checks.yaml
├── state/                # 執行結果（auto）
├── snapshots/            # 安裝前備份
└── logs/
```

新增 plugin 只要在對應目錄丟一個 YAML，下次 `sut scan` 自動載入。

## Self-discovery

Research Agent 掃描時會在 `meta_discoveries` 回報值得新增的 source / scorer / action。
建議而已，不自動安裝。
