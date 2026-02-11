# Claude Code Context Handoff

Automatic context preservation for Claude Code sessions, including `/clear` transitions.

## What this fixes

Long-running sessions degrade after repeated context compactions. This plugin preserves critical context and restores it after both `compact` and `clear` lifecycle transitions.

## Architecture

This project now has two layers:

1. Hook layer (always-on)
- `PreCompact` -> captures context before auto-compact or `/compact`
- `SessionEnd(clear)` -> captures context before `/clear` tears down session
- `SessionStart(compact|clear)` -> restores context as `additionalContext`

2. Supervisor layer (optional, recommended)
- `claude-handoff-supervisor.py` launches Claude and rewrites manual `/compact` to `/clear`
- This avoids waiting on manual compaction, which hooks cannot rewrite by themselves

## Workflow

```text
auto-compact or /compact
    -> PreCompact hook writes handoff
    -> SessionStart(compact) restores handoff

/clear
    -> SessionEnd(clear) writes handoff (and latest pointer)
    -> SessionStart(clear) restores handoff

recommended manual path:
    use supervisor
    user types /compact
    supervisor rewrites to /clear
    clear transition hooks handle capture+restore
```

## Install

```bash
git clone https://github.com/who96/claude-code-context-handoff.git
cd claude-code-context-handoff
./install.sh
```

Installer actions:
- Copies scripts to `/Users/<you>/.claude/hooks/`
- Backs up `/Users/<you>/.claude/settings.json`
- Registers `PreCompact`, `SessionEnd(clear)`, `SessionStart(compact|clear)` hooks
- Creates `/Users/<you>/.claude/handoff/`

Restart Claude Code after install.

## Recommended launch mode

```bash
~/.claude/hooks/claude-handoff-supervisor.py
```

This gives command rewrite:
- `/compact` -> `/clear`

If you want plain passthrough:

```bash
~/.claude/hooks/claude-handoff-supervisor.py --no-rewrite
```

## Handoff files

Generated artifacts:
- `~/.claude/handoff/<session_id>.md`
- `~/.claude/handoff/latest-handoff.md`
- `~/.claude/handoff/latest-handoff.json`

`latest-handoff.md` is used as fallback restore source for `SessionStart(clear)` when the new session id has no direct file yet.
Fallback safety guards:
- same `cwd` (if both sides provide it)
- max age window (`HANDOFF_LATEST_MAX_AGE_SEC`, default `900`)

## What gets preserved

- Last 15 user messages (deduplicated, 85% threshold)
- Last 10 assistant snippets (junk filtered, truncated)
- File paths extracted from tool input (`file_path` / `path`)
- Command-like strings are filtered out from path extraction

Tune via env vars:

```bash
export HANDOFF_MAX_USER_MESSAGES=20
export HANDOFF_MAX_ASSISTANT_CHARS=1000
export HANDOFF_DEDUP_THRESHOLD=0.90
export HANDOFF_LATEST_MAX_AGE_SEC=900
```

## Verify

Run:

```bash
./test.sh
```

Quick manual verification:

```bash
/clear
ls -la ~/.claude/handoff/
```

## Known limits

- Hooks cannot rewrite slash commands directly.
- Automatic replacement of `/compact` requires the external supervisor.
- Auto-compact itself is still controlled by Claude Code; this plugin only preserves/recovers context around it.

Supervisor argument passthrough supports direct Claude flags:

```bash
~/.claude/hooks/claude-handoff-supervisor.py --model sonnet --debug
```

## Uninstall

```bash
./uninstall.sh
```

## License

MIT. See `/Users/huluobo/workSpace/claude-code-context-handoff/LICENSE`.
