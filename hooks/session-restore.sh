#!/usr/bin/env bash
# SessionStart hook: restore handoff context after compact.
# Reads the handoff file keyed by session_id so multiple agents don't collide.

set -euo pipefail

HANDOFF_DIR="${HOME}/.claude/handoff"

# Read stdin JSON to get session_id
input=$(cat)
session_id=$(echo "$input" | python3 -c "import sys,json; print(json.load(sys.stdin).get('session_id',''))" 2>/dev/null || echo "")

if [ -z "$session_id" ]; then
  exit 0
fi

HANDOFF_FILE="${HANDOFF_DIR}/${session_id}.md"

# No handoff file for this session → nothing to restore
if [ ! -f "$HANDOFF_FILE" ]; then
  exit 0
fi

# Read handoff content
handoff_content=$(cat "$HANDOFF_FILE")

# Check if file is non-empty
if [ -z "$handoff_content" ]; then
  exit 0
fi

# Escape for JSON
escape_for_json() {
  local input="$1"
  local output=""
  local i char
  for (( i=0; i<${#input}; i++ )); do
    char="${input:$i:1}"
    case "$char" in
      $'\\') output+='\\';;
      '"') output+='\"';;
      $'\n') output+='\n';;
      $'\r') output+='\r';;
      $'\t') output+='\t';;
      *) output+="$char";;
    esac
  done
  printf '%s' "$output"
}

escaped_content=$(escape_for_json "$handoff_content")

# Inject as additional context
cat <<EOF
{
  "hookSpecificOutput": {
    "hookEventName": "SessionStart",
    "additionalContext": "<context-handoff>\nThe following is a context snapshot from the previous compaction cycle. Use it to maintain continuity.\n\n${escaped_content}\n</context-handoff>"
  }
}
EOF

exit 0
