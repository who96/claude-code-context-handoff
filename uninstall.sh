#!/usr/bin/env bash
# Claude Code Context Handoff - Uninstallation Script
# Removes hooks and restores settings.json entries.

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

CLAUDE_DIR="${HOME}/.claude"
HOOKS_DIR="${CLAUDE_DIR}/hooks"
HANDOFF_DIR="${CLAUDE_DIR}/handoff"
SETTINGS_FILE="${CLAUDE_DIR}/settings.json"

echo -e "${YELLOW}Claude Code Context Handoff - Uninstaller${NC}"
echo "================================================"
echo ""

echo "This will:"
echo "  - Remove installed scripts from ${HOOKS_DIR}"
echo "  - Remove hook registrations from settings.json"
echo "  - Optionally remove handoff files from ${HANDOFF_DIR}"
echo ""
read -r -p "Continue? (y/N) " reply
if [[ ! "$reply" =~ ^[Yy]$ ]]; then
    echo "Uninstallation cancelled."
    exit 0
fi

echo ""
echo "Removing installed files..."

files_to_remove=(
    "${HOOKS_DIR}/pre-compact-handoff.py"
    "${HOOKS_DIR}/session-end-handoff.py"
    "${HOOKS_DIR}/session-restore.sh"
    "${HOOKS_DIR}/handoff_core.py"
    "${HOOKS_DIR}/claude-handoff-supervisor.py"
)

for file in "${files_to_remove[@]}"; do
    if [ -f "$file" ]; then
        rm -f "$file"
        echo -e "${GREEN}✓${NC} Removed $(basename "$file")"
    fi
done

echo ""
echo "Removing hooks from settings.json..."

if [ -f "$SETTINGS_FILE" ]; then
    backup_file="${SETTINGS_FILE}.backup.$(date +%Y%m%d_%H%M%S)"
    cp "$SETTINGS_FILE" "$backup_file"
    echo "Backup created: ${backup_file}"

    if command -v jq >/dev/null 2>&1; then
        temp_file="$(mktemp)"
        jq '
          .hooks = (.hooks // {}) |
          .hooks.PreCompact = ((.hooks.PreCompact // [])
            | map(select(((.hooks[0].command // "") | contains("pre-compact-handoff")) | not))) |
          .hooks.SessionEnd = ((.hooks.SessionEnd // [])
            | map(select(((.hooks[0].command // "") | contains("session-end-handoff")) | not))) |
          .hooks.SessionStart = ((.hooks.SessionStart // [])
            | map(select(((.hooks[0].command // "") | contains("session-restore.sh")) | not))) |
          if .hooks.PreCompact == [] then del(.hooks.PreCompact) else . end |
          if .hooks.SessionEnd == [] then del(.hooks.SessionEnd) else . end |
          if .hooks.SessionStart == [] then del(.hooks.SessionStart) else . end |
          if .hooks == {} then del(.hooks) else . end
        ' "$SETTINGS_FILE" > "$temp_file"
        mv "$temp_file" "$SETTINGS_FILE"
        echo -e "${GREEN}✓${NC} Hook entries removed"
    else
        python3 - "$SETTINGS_FILE" <<'PY'
import json
import pathlib
import sys

settings_path = pathlib.Path(sys.argv[1])
try:
    settings = json.loads(settings_path.read_text(encoding="utf-8"))
except Exception:
    settings = {}

hooks = settings.get("hooks", {})

def drop(entries, marker):
    result = []
    for entry in entries:
        command = ""
        try:
            command = str(entry.get("hooks", [{}])[0].get("command", ""))
        except Exception:
            command = ""
        if marker in command:
            continue
        result.append(entry)
    return result

if "PreCompact" in hooks:
    hooks["PreCompact"] = drop(hooks["PreCompact"], "pre-compact-handoff")
    if not hooks["PreCompact"]:
        del hooks["PreCompact"]

if "SessionEnd" in hooks:
    hooks["SessionEnd"] = drop(hooks["SessionEnd"], "session-end-handoff")
    if not hooks["SessionEnd"]:
        del hooks["SessionEnd"]

if "SessionStart" in hooks:
    hooks["SessionStart"] = drop(hooks["SessionStart"], "session-restore.sh")
    if not hooks["SessionStart"]:
        del hooks["SessionStart"]

if hooks:
    settings["hooks"] = hooks
elif "hooks" in settings:
    del settings["hooks"]

settings_path.write_text(json.dumps(settings, indent=2), encoding="utf-8")
print("Hook entries removed")
PY
        echo -e "${GREEN}✓${NC} Hook entries removed"
    fi
else
    echo -e "${YELLOW}settings.json not found; skipped hook cleanup${NC}"
fi

echo ""
read -r -p "Remove handoff files from ${HANDOFF_DIR}? (y/N) " remove_handoff
if [[ "$remove_handoff" =~ ^[Yy]$ ]]; then
    if [ -d "$HANDOFF_DIR" ]; then
        rm -rf "$HANDOFF_DIR"
        echo -e "${GREEN}✓${NC} Removed ${HANDOFF_DIR}"
    else
        echo -e "${YELLOW}No handoff directory found${NC}"
    fi
else
    echo "Handoff files preserved at ${HANDOFF_DIR}"
fi

echo ""
echo "================================================"
echo -e "${GREEN}Uninstallation complete!${NC}"
echo "Restart Claude Code to apply changes."
echo "================================================"
