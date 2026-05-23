# Claude Code Usage Analytics

## Data Collection

A statusline wrapper (`statusline-wrapper.sh`) logs the full JSON payload that Claude Code passes to the statusline command on every turn. Logs are stored at:

```
~/.local/share/claude-statusline-logs/YYYY-MM-DD.jsonl
```

One JSON object per line, one line per statusline update (roughly per assistant turn).

Logging is opt-in per machine: the wrapper only writes when the log directory already exists. To enable on a machine:

```sh
mkdir -p "${XDG_DATA_HOME:-$HOME/.local/share}/claude-statusline-logs"
```

If the directory is absent, the wrapper passes through silently (no log writes, no errors). This is how the devbox skips analytics while the Mac keeps them.

## Status JSON Schema

Each line contains:

```json
{
  "session_id": "uuid",
  "transcript_path": "/path/to/session.jsonl",
  "cwd": "/working/directory",
  "model": { "id": "claude-opus-4-6[1m]", "display_name": "Opus 4.6 (1M context)" },
  "workspace": { "current_dir": "...", "project_dir": "...", "added_dirs": [] },
  "version": "2.1.92",
  "cost": {
    "total_cost_usd": 17.89,
    "total_duration_ms": 245869727,
    "total_api_duration_ms": 2002812,
    "total_lines_added": 16,
    "total_lines_removed": 1
  },
  "context_window": {
    "total_input_tokens": 3232,
    "total_output_tokens": 106437,
    "context_window_size": 1000000,
    "current_usage": {
      "input_tokens": 1,
      "output_tokens": 1,
      "cache_creation_input_tokens": 300,
      "cache_read_input_tokens": 175399
    },
    "used_percentage": 18,
    "remaining_percentage": 82
  },
  "exceeds_200k_tokens": false,
  "rate_limits": {
    "five_hour": { "used_percentage": 15, "resets_at": 1775559600 },
    "seven_day": { "used_percentage": 51, "resets_at": 1775638800 }
  }
}
```

## Field Reliability

| Field | Cumulative | Accurate | Notes |
|---|---|---|---|
| `cost.total_cost_usd` | Yes | **Exact** | Includes all models, subagents, compact, cache |
| `context_window.total_input_tokens` | Yes | **Exact** | Summed across all models in session |
| `context_window.total_output_tokens` | Yes | **Exact** | Summed across all models in session |
| `context_window.current_usage.*` | No | Per-call | Last API call only, not session total |
| `rate_limits.*` | N/A | Exact | Account-level usage windows |

### What's NOT in the data

- **Cumulative cache tokens** — Claude Code tracks these internally (`cacheReadInputTokens`, `cacheCreationInputTokens` per model in `R_.modelUsage`) but does not expose them in the status JSON.
- **Per-model token split** — `total_input_tokens` / `total_output_tokens` are summed across all models (opus, sonnet, haiku subagents). No breakdown.
- **Per-model cost split** — Same issue. `total_cost_usd` is a single sum.

## Key Findings (from binary analysis of Claude Code v2.1.92)

### Internal Token Tracking

Claude Code uses a global `R_.modelUsage` object keyed by model name. Each model entry tracks: `inputTokens`, `outputTokens`, `cacheReadInputTokens`, `cacheCreationInputTokens`, `webSearchRequests`, `costUSD`.

Streaming deduplication uses **replace-then-add-once** semantics:
- `gKH` replaces per-chunk values during streaming (takes latest non-zero)
- `wQ_` adds the final single-response usage to session totals at `message_stop`
- No double-counting of streaming chunks

All forks (compact agents, subagents, speculation, memory extraction) feed into the same global counters.

### Internal Pricing (hardcoded in binary, per M tokens)

| Model | Input | Output | Cache Write | Cache Read |
|---|---|---|---|---|
| Opus 4 (claude-opus-4-20250514) | $15 | $75 | $18.75 | $1.50 |
| **Opus 4.6 (claude-opus-4-6)** | **$5** | **$25** | **$6.25** | **$0.50** |
| Sonnet 4.6 | $5 | $25 | $6.25 | $0.50 |
| Sonnet 4.6 fast mode | $30 | $150 | $37.50 | $3.00 |
| Haiku 4.5 | $0.80 | $4 | $1.00 | $0.08 |

Note: Opus 4.6 uses the **same rates as Sonnet 4** (`UP_` variable), not Opus 4 rates (`Rwq`). This is determined by `mWH()` which returns `UP_` for standard speed and `aK4` for fast mode.

### Pricing vs Published API Rates

Published API rates (from anthropic.com) are ~1.21x higher than Claude Code's internal rates for Opus/Sonnet, and ~1.51x for Haiku. Claude Code's `total_cost_usd` reflects its internal rates, not API prices.

### ccusage Tool Discrepancies

ccusage (v18.0.10) uses LiteLLM pricing which differs from both Claude Code's internal rates and published API rates. Additionally:
- It separates subagent costs into their own rows (not under parent session)
- Its deduplication takes the first entry per `messageId:requestId` hash, undercounting output tokens
- It has no Opus 4.6-specific rate — likely falls back to generic rates

### ccstatusline Token Display

- `tokens-input` / `tokens-output`: reads from `context_window.total_input_tokens` / `total_output_tokens` — **correct**
- `tokens-cached`: reads from naive JSONL sum (no streaming dedup) — **wrong, inflated ~2-3x**
- `session-cost`: reads from `cost.total_cost_usd` — **correct**

## Interpreting the Data

### Per-session analytics

Take the **last entry** per `session_id` in a day's JSONL — that has the final cumulative totals.

```bash
# Last entry per session for a given day
jq -s 'group_by(.session_id) | map(last)' ~/.local/share/claude-statusline-logs/2026-04-07.jsonl
```

### Per-day cost

```bash
# Sum of final cost per session
jq -s 'group_by(.session_id) | map(last) | map(.cost.total_cost_usd) | add' ~/.local/share/claude-statusline-logs/2026-04-07.jsonl
```

### Cache cost approximation

For single-model sessions (opus-4-6 only):

```
cache_cost ≈ total_cost_usd - total_input_tokens × $5/M - total_output_tokens × $25/M
cache_tokens_estimate ≈ cache_cost / $0.50/M
```

This overestimates cache tokens slightly (cache writes cost 12.5x more than reads per token). For sessions with mixed models (subagents using haiku/sonnet), the approximation degrades because input/output rates differ per model.

### Rate limit tracking

`rate_limits.five_hour` and `rate_limits.seven_day` show account-level usage windows with reset timestamps. Useful for tracking consumption patterns.

## Future Expansion

### Feature requests for Claude Code

The single highest-impact change would be adding cumulative cache tokens to the status JSON:

```json
"context_window": {
  "total_input_tokens": 3232,
  "total_output_tokens": 106437,
  "total_cache_read_input_tokens": 30426543,
  "total_cache_creation_input_tokens": 802411,
  ...
}
```

The data already exists internally (`fxH()` / `YxH()`). Exposing it would enable exact token accounting.

Second priority: per-model breakdown (the `R_.modelUsage` map), which would enable exact cost attribution even with mixed-model sessions.

### Analytics pipeline ideas

- **Daily/weekly cost dashboard** — aggregate last-entry-per-session across date files
- **Session efficiency metrics** — cost per lines_added, api_duration vs wall_duration ratio
- **Rate limit forecasting** — track `five_hour` and `seven_day` percentages over time to predict throttling
- **Context utilization** — track `used_percentage` to understand how often sessions approach the 1M limit
- **Model mix analysis** — correlate `model.id` with cost patterns across sessions (limited to main model visibility)
- **Project-level costs** — group by `workspace.project_dir` for per-project spend tracking
