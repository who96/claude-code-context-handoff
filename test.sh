#!/usr/bin/env bash
# Test script for Claude Code Context Handoff

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

CLAUDE_DIR="${HOME}/.claude"
HOOKS_DIR="${CLAUDE_DIR}/hooks"
HANDOFF_DIR="${CLAUDE_DIR}/handoff"
SETTINGS_FILE="${CLAUDE_DIR}/settings.json"

echo "Claude Code Context Handoff - Test Suite"
echo "========================================"
echo ""

TESTS_PASSED=0
TESTS_FAILED=0

pass() {
    echo -e "${GREEN}✓ PASS${NC} $1"
    TESTS_PASSED=$((TESTS_PASSED + 1))
}

fail() {
    echo -e "${RED}✗ FAIL${NC} $1"
    TESTS_FAILED=$((TESTS_FAILED + 1))
}

skip() {
    echo -e "${YELLOW}⊘ SKIP${NC} $1"
}

echo "Test 1: Required scripts exist"
required=(
    "${HOOKS_DIR}/pre-compact-handoff.py"
    "${HOOKS_DIR}/session-end-handoff.py"
    "${HOOKS_DIR}/session-restore.sh"
    "${HOOKS_DIR}/handoff_core.py"
    "${HOOKS_DIR}/claude-handoff-supervisor.py"
)
missing=0
for file in "${required[@]}"; do
    if [ ! -f "$file" ]; then
        missing=1
        echo "  missing: $(basename "$file")"
    fi
done
if [ "$missing" -eq 0 ]; then
    pass "All scripts present"
else
    fail "One or more scripts missing"
fi

echo "Test 2: Executable permissions"
if [ -x "${HOOKS_DIR}/pre-compact-handoff.py" ] && \
   [ -x "${HOOKS_DIR}/session-end-handoff.py" ] && \
   [ -x "${HOOKS_DIR}/session-restore.sh" ] && \
   [ -x "${HOOKS_DIR}/claude-handoff-supervisor.py" ]; then
    pass "Scripts executable"
else
    fail "Scripts not executable"
fi

echo "Test 3: Handoff directory exists"
if [ -d "${HANDOFF_DIR}" ]; then
    pass "Handoff dir present"
else
    fail "Handoff dir missing"
fi

echo "Test 4: Hooks registered in settings.json"
if [ -f "$SETTINGS_FILE" ] && command -v jq >/dev/null 2>&1; then
    if jq -e '.hooks.PreCompact' "$SETTINGS_FILE" >/dev/null 2>&1 && \
       jq -e '.hooks.SessionStart' "$SETTINGS_FILE" >/dev/null 2>&1 && \
       jq -e '.hooks.SessionEnd' "$SETTINGS_FILE" >/dev/null 2>&1; then
        pass "PreCompact + SessionStart + SessionEnd registered"
    else
        fail "Hook registration incomplete"
    fi
else
    skip "jq or settings.json missing"
fi

echo "Test 5: PreCompact hook produces handoff"
mkdir -p "$HANDOFF_DIR"
test_session="test-$(date +%s)"
test_transcript="$(mktemp)"

cat > "$test_transcript" <<'EOF'
{"type":"user","message":{"content":"Please update /tmp/demo/file_a.py and avoid duplicate work."}}
{"type":"assistant","message":{"content":[{"type":"text","text":"I will edit the file now."},{"type":"tool_use","input":{"file_path":"/tmp/demo/file_a.py"}}]}}
{"type":"user","message":{"content":"Please update /tmp/demo/file_a.py and avoid duplicate work."}}
EOF

pre_output=$(echo "{\"session_id\":\"${test_session}\",\"transcript_path\":\"${test_transcript}\"}" | \
  python3 "${HOOKS_DIR}/pre-compact-handoff.py" 2>&1 || true)

if echo "$pre_output" | grep -q "systemMessage" && [ -f "${HANDOFF_DIR}/${test_session}.md" ]; then
    pass "PreCompact hook generated session handoff"
else
    fail "PreCompact hook did not generate expected output"
    echo "  output: $pre_output"
fi

echo "Test 6: SessionEnd(clear) refreshes latest-handoff"
end_output=$(echo "{\"session_id\":\"${test_session}\",\"source\":\"clear\",\"cwd\":\"/tmp/project-a\",\"transcript_path\":\"${test_transcript}\"}" | \
  python3 "${HOOKS_DIR}/session-end-handoff.py" 2>&1 || true)

if echo "$end_output" | grep -q "systemMessage" && [ -f "${HANDOFF_DIR}/latest-handoff.md" ]; then
    pass "SessionEnd hook generated latest-handoff"
else
    fail "SessionEnd hook failed to generate latest-handoff"
    echo "  output: $end_output"
fi

echo "Test 7: SessionStart(clear) restores from latest-handoff fallback"
start_output=$(echo '{"session_id":"new-session-after-clear","source":"clear","cwd":"/tmp/project-a"}' | \
  bash "${HOOKS_DIR}/session-restore.sh" 2>&1 || true)

if echo "$start_output" | grep -q "additionalContext"; then
    pass "SessionStart clear fallback restore works"
else
    fail "SessionStart clear fallback restore failed"
    echo "  output: $start_output"
fi

echo "Test 8: SessionStart(clear) blocks fallback on cwd mismatch"
mismatch_output=$(echo '{"session_id":"new-session-after-clear","source":"clear","cwd":"/tmp/project-b"}' | \
  bash "${HOOKS_DIR}/session-restore.sh" 2>&1 || true)

if [ -z "$mismatch_output" ]; then
    pass "cwd mismatch guard blocks unsafe fallback"
else
    fail "cwd mismatch guard did not block fallback"
    echo "  output: $mismatch_output"
fi

echo "Test 9: Supervisor accepts passthrough flags without '--'"
passthrough_output=$(
  python3 "${HOOKS_DIR}/claude-handoff-supervisor.py" --quiet --claude-bin /bin/true --model sonnet 2>&1 || true
)
if echo "$passthrough_output" | grep -qi "unrecognized arguments"; then
    fail "Supervisor still rejects passthrough flags"
    echo "  output: $passthrough_output"
else
    pass "Supervisor accepts passthrough flags"
fi

echo "Test 10: Supervisor rewrites /compact to /clear"
rewrite_output=$(
  printf '/compact\n' | python3 "${HOOKS_DIR}/claude-handoff-supervisor.py" --quiet --claude-bin /bin/cat 2>&1 || true
)
if echo "$rewrite_output" | grep -q -- "/clear"; then
    pass "Supervisor rewrite path works"
else
    fail "Supervisor rewrite path missing"
    echo "  output: $rewrite_output"
fi

rm -f "$test_transcript"
rm -f "${HANDOFF_DIR}/${test_session}.md"

echo ""
echo "========================================"
echo "Test Results:"
echo -e "  ${GREEN}Passed: ${TESTS_PASSED}${NC}"
if [ "$TESTS_FAILED" -gt 0 ]; then
    echo -e "  ${RED}Failed: ${TESTS_FAILED}${NC}"
else
    echo "  Failed: 0"
fi
echo "========================================"

if [ "$TESTS_FAILED" -eq 0 ]; then
    echo -e "${GREEN}All tests passed!${NC}"
    exit 0
fi

echo -e "${RED}Some tests failed. Check installation.${NC}"
exit 1
