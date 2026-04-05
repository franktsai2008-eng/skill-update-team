# Skill Update Team (SUT)

Automated AI tool discovery, security audit, and installation agent for [Claude Code](https://docs.anthropic.com/en/docs/claude-code).

SUT scans GitHub, Reddit, YouTube, and Anthropic changelog for new MCP servers, Claude Code plugins, and AI tools — scores them, checks security, and recommends only what's relevant to you.

## How It Works

```
You: /skill-update-team
       ↓
Orchestrator (SKILL.md) reads plugin YAMLs, collects your environment info
       ↓
Spawns Research Agent (subagent, sonnet) → scans all sources → scores → JSON report
       ↓
Shows you only high-scoring recommendations with:
  - What it does (features)
  - Why it's relevant to YOUR setup
  - Score breakdown
  - Deprecated skill cleanup suggestions
       ↓
You: /skill-update-team approve <id>
       ↓
Spawns Security Auditor (subagent) → 6 checks → Snapshot → Install → Smoke test
```

## Architecture

SUT runs as a **Claude Code skill** using the **multi-agent pattern**:

- **SKILL.md** = lightweight orchestrator (runs in your main conversation)
- **Research Agent** = heavy lifting, spawned via `Agent(model="sonnet")` — isolated context
- **Security Auditor** = spawned per-tool audit, also via `Agent(model="sonnet")`

This keeps your main conversation clean while the subagents do the expensive work.

## Quick Start

### 1. Prerequisites

- [Claude Code CLI](https://docs.anthropic.com/en/docs/claude-code) installed and authenticated
- [Firecrawl MCP](https://github.com/anthropics/claude-code/blob/main/docs/mcp.md) connected (for web scraping)

### 2. Install

```bash
git clone https://github.com/franktsai2008-eng/skill-update-team.git ~/skill-update-team
cd ~/skill-update-team && chmod +x install.sh && ./install.sh
```

The install script creates `~/.claude/skills/` and symlinks this repo into it. Restart Claude Code after installation.

### 3. Use

Just talk to Claude Code:

```
/skill-update-team                # Scan for new tools + show report
/skill-update-team report         # View last scan report
/skill-update-team check <id>     # Run security audit on a finding
/skill-update-team approve <id>   # Install (security check → snapshot → install → smoke test)
/skill-update-team reject <id>    # Reject (influences future scoring)
/skill-update-team defer <id>     # Defer for later
/skill-update-team rollback       # Revert last installation
/skill-update-team health         # Check installed tools health
```

No CLI scripts needed — everything runs through Claude Code's skill and agent system.

## Where to Use

| Platform | How | Notes |
|----------|-----|-------|
| **Claude Code (CLI)** | Type `/skill-update-team` | Best experience |
| **Claude Code (IDE)** | Same — in the chat | VS Code / JetBrains |
| **Co-work / Chat** | Not supported | Requires Agent tool |

## Features

### Tool Discovery & Scoring

Each discovered tool is scored across 5 dimensions:

| Scorer | Weight | What It Measures |
|--------|--------|------------------|
| relevance | 0.30 | Does it enhance your current setup or fill a gap? |
| github-stars | 0.25 | Community adoption |
| recency | 0.20 | How recently updated |
| community | 0.15 | Found in multiple sources |
| preference | 0.10 | Matches your past approve/reject history |

**Final score** = weighted sum. Only **Important (>= 0.65)** and **Critical (>= 0.85)** are actively recommended.

### Deprecated Skill Cleanup

During scans, SUT also checks your installed MCP servers and skills for:
- Tools that have been **superseded** by a newer/better alternative
- Tools that are **unmaintained** (no updates in 180+ days, archived repos)
- Tools with **overlapping functionality** (>80% overlap with another installed tool)
- Tools that have known **security vulnerabilities**

These appear in the report under "Cleanup Suggestions" with recommended actions.

### Security

Every tool goes through 6 automated security checks before installation:

| Check | Severity | What It Checks |
|-------|----------|----------------|
| repo-trust | **block** | Stars, owner reputation, LICENSE, not archived |
| code-review | **block** | No `curl\|sh`, no `eval()`, no reading `~/.ssh` etc. |
| permissions-scope | **block** | No filesystem global access, no sudo |
| dependency-audit | warn | npm audit, CVE, typosquatting |
| data-exfil | **block** | No unauthorized data transmission |
| freshness | warn | Last commit within 180 days |

- Any **block** fails → **BLOCKED** (refuses to install)
- Any **warn** fails → **CAUTION** (asks for confirmation)
- All pass → **SAFE**

A snapshot of your Claude settings is saved before every install. Say `/skill-update-team rollback` to revert.

### Self-Discovery

During scans, the Research Agent may discover new sources, scoring dimensions, or install methods worth adding. These appear in the report as suggestions — never auto-installed.

## Plugin Architecture

SUT is fully extensible. Drop a YAML file in the right directory and it auto-loads on next scan.

```
skill-update-team/
├── SKILL.md              # Skill entry point (orchestrator)
├── config.yaml           # Default config
├── prompts/
│   ├── research.md       # Research Agent prompt
│   └── security-audit.md # Security Auditor prompt
├── sources/              # Where to search (GitHub, Reddit, YouTube...)
├── scorers/              # How to score (stars, recency, relevance...)
├── actions/              # How to install (mcp add, npm, pip, skill...)
└── security/
    └── checks.yaml       # Security check rules
```

### Add a Source

Create `sources/my-source.yaml`:

```yaml
name: my-source
enabled: true
description: Search my favorite tool registry
instructions: |
  Use firecrawl_search to search "https://example.com/tools"
  for new Claude-compatible tools updated in the last {{7_DAYS_AGO}} days.
```

### Add a Scorer

Create `scorers/my-scorer.yaml`:

```yaml
name: my-scorer
enabled: true
weight: 0.10
description: Score based on my custom criteria
scoring_rules: |
  1.0 = perfect match
  0.5 = partial match
  0.0 = no match
```

> Remember to adjust other scorer weights so they still sum to ~1.0.

### Add an Action

Create `actions/my-action.yaml`:

```yaml
name: my-action
enabled: true
type: custom
install_template: "my-tool install {package}"
smoke_test: "my-tool list | grep {name}"
rollback: "my-tool uninstall {package}"
```

## FAQ

**Q: How much does a scan cost?**
A: ~$0.10-0.30 per scan (subagents use Sonnet).

**Q: Can I use a different model?**
A: The orchestrator runs on whatever model your Claude Code session uses. Subagents default to Sonnet for cost efficiency.

**Q: What if an install breaks something?**
A: Say `/skill-update-team rollback`. It restores your Claude settings from the pre-install snapshot.

**Q: Does it auto-install anything?**
A: No. Every installation requires your explicit `/skill-update-team approve`.

## License

MIT
