# Skill Update Team (SUT)

Automated AI tool discovery, security audit, and installation agent for [Claude Code](https://docs.anthropic.com/en/docs/claude-code).

SUT scans GitHub, Reddit, YouTube, and Anthropic changelog for new MCP servers, Claude Code plugins, and AI tools — scores them, checks security, and recommends only what's relevant to you.

## How It Works

```
You: sut scan
       ↓
Research Agent (claude -p) scans all sources → scores each tool → generates report
       ↓
Shows you only high-scoring recommendations with:
  - What it does (features)
  - Why it's relevant to YOUR setup
  - Score breakdown
  - One-command install
       ↓
You: sut approve <id>
       ↓
Security audit (6 checks) → Snapshot → Install → Smoke test
```

## Quick Start

### 1. Prerequisites

- [Claude Code CLI](https://docs.anthropic.com/en/docs/claude-code) installed and authenticated
- [Firecrawl MCP](https://github.com/anthropics/claude-code/blob/main/docs/mcp.md) connected (for web scraping)
- macOS / Linux, bash, python3, jq

### 2. Install

```bash
git clone https://github.com/FrankTsai77/skill-update-team.git ~/skill-update-team
chmod +x ~/skill-update-team/run.sh

# Add to PATH (pick one)
ln -sf ~/skill-update-team/run.sh ~/bin/sut        # if ~/bin is in PATH
# or
echo 'alias sut="~/skill-update-team/run.sh"' >> ~/.zshrc && source ~/.zshrc
```

### 3. Use

```bash
sut scan              # Scan for new tools (the main command)
sut report            # View last scan report
sut check <id>        # Run security audit on a finding
sut approve <id>      # Install (auto: security check → snapshot → install → smoke test)
sut reject <id>       # Reject (influences future scoring)
sut defer <id>        # Defer for later
sut rollback          # Revert last installation
```

That's it. Run `sut scan` when you want to check for new tools.

## Where to Use

| Platform | How | Notes |
|----------|-----|-------|
| **Claude Code (CLI)** | Type `sut scan` in terminal | Best experience — full interactive flow |
| **Claude Code (IDE)** | Same — use the built-in terminal | VS Code / JetBrains both work |
| **Co-work / Chat** | Not supported | Requires CLI access (`claude -p`) |

SUT is a CLI tool that calls `claude -p` (print mode) internally. It needs terminal access, so it only works in Claude Code or any terminal environment.

## Security

Every tool goes through 6 automated security checks before installation:

| Check | Severity | What It Checks |
|-------|----------|----------------|
| repo-trust | **block** | Stars, owner reputation, LICENSE, not archived |
| code-review | **block** | No `curl\|sh`, no `eval()`, no reading `~/.ssh` etc. |
| permissions-scope | **block** | No filesystem global access, no sudo |
| dependency-audit | warn | npm audit, CVE, typosquatting |
| data-exfil | **block** | No unauthorized data transmission |
| freshness | warn | Last commit within 180 days |

- Any **block** check fails → **BLOCKED** (refuses to install)
- Any **warn** check fails → **CAUTION** (asks for confirmation)
- All pass → **SAFE**

A snapshot of your Claude settings is saved before every install. Run `sut rollback` to revert.

## Plugin Architecture

SUT is fully extensible. Drop a YAML file in the right directory and it auto-loads on next scan.

```
skill-update-team/
├── run.sh                # CLI entry point
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

## How Scoring Works

Each discovered tool is scored across 5 dimensions:

| Scorer | Weight | What It Measures |
|--------|--------|------------------|
| relevance | 0.30 | Does it enhance your current setup or fill a gap? |
| github-stars | 0.25 | Community adoption |
| recency | 0.20 | How recently updated |
| community | 0.15 | Found in multiple sources |
| preference | 0.10 | Matches your past approve/reject history |

**Final score** = weighted sum. Only **Important (>= 0.65)** and **Critical (>= 0.85)** are actively recommended.

## Self-Discovery

During scans, the Research Agent may discover new sources, scoring dimensions, or install methods worth adding. These appear in the report under "Self-discovery" as suggestions — never auto-installed.

## FAQ

**Q: How much does a scan cost?**
A: ~$0.10-0.30 per scan (uses Claude Sonnet with a $0.50 budget cap).

**Q: Can I use a different model?**
A: Edit `config.yaml` → `claude.model`. Opus is more thorough but costs more.

**Q: What if an install breaks something?**
A: Run `sut rollback`. It restores your Claude settings from the pre-install snapshot.

**Q: Does it auto-install anything?**
A: No. Every installation requires your explicit `sut approve`.

## License

MIT
