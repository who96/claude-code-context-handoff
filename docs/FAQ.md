# FAQ

## Why didn't hook-only replacement from `/compact` to `/clear` work?

Because Claude hooks can observe lifecycle events but cannot directly rewrite slash commands.  
Use `claude-handoff-supervisor.py` for command rewrite.

## What changed in v1.1?

- Added `SessionEnd(clear)` handoff capture
- Added `SessionStart(clear)` restore path
- Added `latest-handoff.md` fallback
- Added external supervisor that rewrites manual `/compact` to `/clear`

## Does this still support auto-compact?

Yes. `PreCompact` + `SessionStart(compact)` still works.

## Does this support `/clear` continuity now?

Yes. `SessionEnd(clear)` writes handoff before teardown, then `SessionStart(clear)` restores it.

## Where are handoff files?

- `~/.claude/handoff/<session_id>.md`
- `~/.claude/handoff/latest-handoff.md`
- `~/.claude/handoff/latest-handoff.json`

## How does clear fallback avoid wrong-session restore?

For `SessionStart(clear)` fallback, the restore now checks:
- latest handoff age (`HANDOFF_LATEST_MAX_AGE_SEC`, default 900s)
- `cwd` match when both capture/start events include `cwd`

## How do I launch with command rewrite?

```bash
~/.claude/hooks/claude-handoff-supervisor.py
```

You can pass Claude flags directly (no mandatory `--` separator):

```bash
~/.claude/hooks/claude-handoff-supervisor.py --model sonnet --debug
```

## How do I disable rewrite but keep passthrough?

```bash
~/.claude/hooks/claude-handoff-supervisor.py --no-rewrite
```

## Does this conflict with other hooks or MCP?

No direct conflict. It only adds hook entries and writes files under `~/.claude/handoff/`.

## Can this run in multi-agent/team mode?

Yes, but `latest-handoff.md` is a global fallback. Session-id files remain the primary source. For heavy parallel runs, prefer direct session-id restores whenever available.
