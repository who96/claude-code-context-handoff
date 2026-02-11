#!/usr/bin/env bash
# SessionStart hook: restore handoff context after compact.
# Reads the handoff file keyed by session_id so multiple agents don't collide.

set -euo pipefail

HANDOFF_DIR="${HOME}/.claude/handoff"
LATEST_HANDOFF_FILE="${HANDOFF_DIR}/latest-handoff.md"
LATEST_META_FILE="${HANDOFF_DIR}/latest-handoff.json"
LATEST_MAX_AGE_SEC="${HANDOFF_LATEST_MAX_AGE_SEC:-900}"

# Read stdin JSON to get session_id, source, and cwd.
input=$(cat)
parsed=$(
  echo "$input" | python3 -c 'import json,sys
try:
    d=json.load(sys.stdin)
    print((d.get("session_id","") or "") + "\t" + (d.get("source","") or "") + "\t" + (d.get("cwd","") or ""))
except Exception:
    print("\t\t")
' 2>/dev/null || echo $'\t\t'
)
session_id="${parsed%%$'\t'*}"
rest="${parsed#*$'\t'}"
source="${rest%%$'\t'*}"
source_cwd="${rest#*$'\t'}"

if [ -z "$session_id" ]; then
  exit 0
fi

SESSION_HANDOFF_FILE="${HANDOFF_DIR}/${session_id}.md"
HANDOFF_FILE=""

# For compact, keep strict session-id lookup.
# For clear, fall back to latest-handoff.md because clear starts a fresh session id.
if [ -f "$SESSION_HANDOFF_FILE" ]; then
  HANDOFF_FILE="$SESSION_HANDOFF_FILE"
elif [ "$source" = "clear" ] && [ -f "$LATEST_HANDOFF_FILE" ]; then
  # Guard fallback by recency and cwd match to reduce cross-session contamination.
  is_valid_latest=$(
    python3 - "$LATEST_META_FILE" "$LATEST_MAX_AGE_SEC" "$source_cwd" <<'PY'
import datetime as dt
import json
import pathlib
import sys

meta_path = pathlib.Path(sys.argv[1])
max_age_sec = int(sys.argv[2])
source_cwd = sys.argv[3]

if not meta_path.exists():
    print("0")
    raise SystemExit(0)

try:
    meta = json.loads(meta_path.read_text(encoding="utf-8"))
except Exception:
    print("0")
    raise SystemExit(0)

generated_at = meta.get("generated_at", "")
meta_cwd = (meta.get("cwd", "") or "").strip()

if source_cwd and meta_cwd and source_cwd.strip() != meta_cwd:
    print("0")
    raise SystemExit(0)

try:
    generated_ts = dt.datetime.fromisoformat(generated_at)
except Exception:
    print("0")
    raise SystemExit(0)

age = dt.datetime.now() - generated_ts
print("1" if age.total_seconds() <= max_age_sec else "0")
PY
  )
  if [ "$is_valid_latest" = "1" ] && [ -f "$LATEST_HANDOFF_FILE" ]; then
    HANDOFF_FILE="$LATEST_HANDOFF_FILE"
  else
    exit 0
  fi
else
  exit 0
fi

handoff_content="$(cat "$HANDOFF_FILE")"

# Check if file is non-empty
if [ -z "$handoff_content" ]; then
  exit 0
fi

python3 - "$HANDOFF_FILE" "$source" <<'PY'
import json
import pathlib
import sys

handoff_file = pathlib.Path(sys.argv[1])
source = sys.argv[2] if len(sys.argv) > 2 else ""
content = handoff_file.read_text(encoding="utf-8", errors="ignore").strip()

if not content:
    raise SystemExit(0)

header = "clear transition" if source == "clear" else "compaction cycle"
payload = {
    "hookSpecificOutput": {
        "hookEventName": "SessionStart",
        "additionalContext": (
            "<context-handoff>\n"
            "The following is a context snapshot restored after a "
            f"{header}. Use it to continue without re-discovery.\n"
            f"- source: {source or 'unknown'}\n"
            f"- handoff_file: {handoff_file}\n\n"
            f"{content}\n"
            "</context-handoff>"
        ),
    }
}

print(json.dumps(payload))
PY

exit 0
