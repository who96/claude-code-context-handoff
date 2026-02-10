#!/usr/bin/env bash
# Claude Code Context Handoff - Uninstallation Script
# Removes hooks and restores settings.json

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Paths
CLAUDE_DIR="${HOME}/.claude"
HOOKS_DIR="${CLAUDE_DIR}/hooks"
HANDOFF_DIR="${CLAUDE_DIR}/handoff"
SETTINGS_FILE="${CLAUDE_DIR}/settings.json"

echo -e "${YELLOW}Claude Code Context Handoff - Uninstaller${NC}"
echo "================================================"
echo ""

# Check if hooks exist
if [ ! -f "${HOOKS_DIR}/pre-compact-handoff.py" ] && [ ! -f "${HOOKS_DIR}/session-restore.sh" ]; then
    echo -e "${YELLOW}No hooks found. Already uninstalled?${NC}"
    exit 0
fi

# Ask for confirmation
echo "This will:"
echo "  - Remove hook scripts from ${HOOKS_DIR}"
echo "  - Remove hook registrations from settings.json"
echo "  - Optionally remove handoff files from ${HANDOFF_DIR}"
echo ""
read -p "Continue? (y/N) " -n 1 -r
echo ""

if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Uninstallation cancelled."
    exit 0
fi

# Remove hook scripts
echo ""
echo "Removing hook scripts..."

if [ -f "${HOOKS_DIR}/pre-compact-handoff.py" ]; then
    rm "${HOOKS_DIR}/pre-compact-handoff.py"
    echo -e "${GREEN}✓${NC} Removed pre-compact-handoff.py"
fi

if [ -f "${HOOKS_DIR}/session-restore.sh" ]; then
    rm "${HOOKS_DIR}/session-restore.sh"
    echo -e "${GREEN}✓${NC} Removed session-restore.sh"
fi

# Remove hooks from settings.json
echo ""
echo "Removing hooks from settings.json..."

if [ ! -f "$SETTINGS_FILE" ]; then
    echo -e "${YELLOW}Warning: settings.json not found${NC}"
else
    # Backup before modification
    BACKUP_FILE="${SETTINGS_FILE}.backup.$(date +%Y%m%d_%H%M%S)"
    cp "$SETTINGS_FILE" "$BACKUP_FILE"
    echo "Backup created: ${BACKUP_FILE}"

    if command -v jq &> /dev/null; then
        # Use jq for safe JSON manipulation
        TEMP_FILE=$(mktemp)

        jq '
        if .hooks.PreCompact then
            .hooks.PreCompact = [.hooks.PreCompact[] | select(.hooks[0].command | contains("pre-compact-handoff") | not)]
        else . end |
        if .hooks.SessionStart then
            .hooks.SessionStart = [.hooks.SessionStart[] | select(.hooks[0].command | contains("session-restore") | not)]
        else . end |
        if .hooks.PreCompact == [] then del(.hooks.PreCompact) else . end |
        if .hooks.SessionStart == [] then del(.hooks.SessionStart) else . end |
        if .hooks == {} then del(.hooks) else . end
        ' "$SETTINGS_FILE" > "$TEMP_FILE"

        mv "$TEMP_FILE" "$SETTINGS_FILE"
        echo -e "${GREEN}✓${NC} Hooks removed from settings.json"
    else
        # Fallback: Python-based removal
        python3 << 'EOF'
import json
import sys

settings_file = sys.argv[1]

try:
    with open(settings_file, 'r') as f:
        settings = json.load(f)
except:
    print("Error reading settings.json")
    sys.exit(1)

if 'hooks' in settings:
    # Remove PreCompact hook
    if 'PreCompact' in settings['hooks']:
        settings['hooks']['PreCompact'] = [
            h for h in settings['hooks']['PreCompact']
            if 'pre-compact-handoff' not in str(h.get('hooks', [{}])[0].get('command', ''))
        ]
        if not settings['hooks']['PreCompact']:
            del settings['hooks']['PreCompact']

    # Remove SessionStart hook
    if 'SessionStart' in settings['hooks']:
        settings['hooks']['SessionStart'] = [
            h for h in settings['hooks']['SessionStart']
            if 'session-restore' not in str(h.get('hooks', [{}])[0].get('command', ''))
        ]
        if not settings['hooks']['SessionStart']:
            del settings['hooks']['SessionStart']

    # Remove hooks key if empty
    if not settings['hooks']:
        del settings['hooks']

with open(settings_file, 'w') as f:
    json.dump(settings, f, indent=2)

print("Hooks removed from settings.json")
EOF
        python3 - "$SETTINGS_FILE"
        echo -e "${GREEN}✓${NC} Hooks removed from settings.json"
    fi
fi

# Ask about handoff files
echo ""
read -p "Remove handoff files from ${HANDOFF_DIR}? (y/N) " -n 1 -r
echo ""

if [[ $REPLY =~ ^[Yy]$ ]]; then
    if [ -d "$HANDOFF_DIR" ]; then
        rm -rf "$HANDOFF_DIR"
        echo -e "${GREEN}✓${NC} Removed ${HANDOFF_DIR}"
    else
        echo -e "${YELLOW}No handoff directory found${NC}"
    fi
else
    echo "Handoff files preserved at ${HANDOFF_DIR}"
fi

# Success message
echo ""
echo "================================================"
echo -e "${GREEN}Uninstallation complete!${NC}"
echo ""
echo "Restart Claude Code to apply changes:"
echo "  ${YELLOW}exit${NC}  # Exit current session"
echo "  ${YELLOW}claude${NC}  # Start new session"
echo ""
echo "Settings backup: ${BACKUP_FILE}"
echo "================================================"
