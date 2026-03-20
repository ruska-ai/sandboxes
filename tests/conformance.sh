#!/usr/bin/env bash
# MCP Sandbox Conformance Test Suite
# Usage: bash tests/conformance.sh http://localhost:3005
set -euo pipefail

SERVER="${1:?Usage: bash tests/conformance.sh <server-url>}"
PASS=0
FAIL=0
SESSION_ID=""
REQ_ID=0

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

pass() { echo -e "${GREEN}PASS${NC}: $1"; PASS=$((PASS+1)); }
fail() { echo -e "${RED}FAIL${NC}: $1 — $2"; FAIL=$((FAIL+1)); }

next_id() { REQ_ID=$((REQ_ID+1)); echo $REQ_ID; }

# JSON-RPC helper — handles both plain JSON and SSE responses
rpc() {
  local method="$1" params="$2" id raw
  id=$(next_id)
  local headers=(-H "Content-Type: application/json" -H "Accept: application/json, text/event-stream")
  [ -n "$SESSION_ID" ] && headers+=(-H "Mcp-Session-Id: $SESSION_ID")
  raw=$(curl -s -D /tmp/mcp_headers -X POST "$SERVER/mcp" \
    "${headers[@]}" \
    -d "{\"jsonrpc\":\"2.0\",\"id\":$id,\"method\":\"$method\",\"params\":$params}")
  # If the response is SSE, extract JSON from the last data: line
  if echo "$raw" | head -1 | grep -q "^event:"; then
    echo "$raw" | grep '^data: ' | sed 's/^data: //' | tail -1
  else
    echo "$raw"
  fi
}

tool_call() {
  local name="$1" args="$2"
  rpc "tools/call" "{\"name\":\"$name\",\"arguments\":$args}"
}

# ============================================================
# 1. Health check
# ============================================================
echo "=== Health Check ==="
HEALTH=$(curl -s "$SERVER/health")
if echo "$HEALTH" | jq -e '.status == "ok"' >/dev/null 2>&1; then
  pass "health returns status: ok"
else
  fail "health returns status: ok" "$HEALTH"
fi

if echo "$HEALTH" | jq -e '.sandbox_id' >/dev/null 2>&1; then
  pass "health returns sandbox_id"
else
  fail "health returns sandbox_id" "$HEALTH"
fi

# ============================================================
# 2. Session initialization
# ============================================================
echo ""
echo "=== Session Init ==="
INIT_RESP=$(rpc "initialize" '{"protocolVersion":"2025-03-26","capabilities":{},"clientInfo":{"name":"test","version":"1.0"}}')
SESSION_ID=$(grep -i 'mcp-session-id' /tmp/mcp_headers | tr -d '\r' | awk '{print $2}')

if [ -n "$SESSION_ID" ]; then
  pass "initialize returns Mcp-Session-Id header"
else
  fail "initialize returns Mcp-Session-Id header" "no session ID"
fi

# Send initialized notification
rpc "notifications/initialized" '{}' >/dev/null

# ============================================================
# 3. Tools list
# ============================================================
echo ""
echo "=== Tools List ==="
TOOLS_RESP=$(rpc "tools/list" '{}')
TOOL_COUNT=$(echo "$TOOLS_RESP" | jq '.result.tools | length')
TOOL_NAMES=$(echo "$TOOLS_RESP" | jq -r '.result.tools[].name' | sort | tr '\n' ',')

# We expect at least 9 tools (execute, exec_command, read, write, edit, grep, glob, ls, upload_file, download_file)
if [ "$TOOL_COUNT" -ge 9 ] 2>/dev/null; then
  pass "tools/list returns >= 9 tools (got $TOOL_COUNT)"
else
  fail "tools/list returns >= 9 tools" "got $TOOL_COUNT: $TOOL_NAMES"
fi

for EXPECTED in execute read write edit grep glob ls upload_file download_file; do
  if echo "$TOOL_NAMES" | grep -q "$EXPECTED"; then
    pass "tool '$EXPECTED' is registered"
  else
    fail "tool '$EXPECTED' is registered" "not found in: $TOOL_NAMES"
  fi
done

# ============================================================
# 4. Execute tool
# ============================================================
echo ""
echo "=== Execute Tool ==="
EXEC_OK=$(tool_call "execute" '{"cmd":"echo hello"}')
if echo "$EXEC_OK" | jq -e '.result.content[0].text' | grep -q "hello"; then
  pass "execute: echo hello returns output"
else
  fail "execute: echo hello returns output" "$EXEC_OK"
fi

if echo "$EXEC_OK" | jq -e '.result._meta.exit_code == 0' >/dev/null 2>&1; then
  pass "execute: success _meta.exit_code == 0"
else
  fail "execute: success _meta.exit_code == 0" "$(echo "$EXEC_OK" | jq '.result._meta')"
fi

EXEC_FAIL=$(tool_call "execute" '{"cmd":"exit 42"}')
if echo "$EXEC_FAIL" | jq -e '.result._meta.exit_code == 42' >/dev/null 2>&1; then
  pass "execute: failure _meta.exit_code == 42"
else
  fail "execute: failure _meta.exit_code matches" "$(echo "$EXEC_FAIL" | jq '.result._meta')"
fi

# ============================================================
# 5. Read tool
# ============================================================
echo ""
echo "=== Read Tool ==="
# Create a test file first
tool_call "write" '{"path":"/workspace/test_read.txt","content":"line1\nline2\nline3"}' >/dev/null
READ_OK=$(tool_call "read" '{"path":"/workspace/test_read.txt"}')
if echo "$READ_OK" | jq -e '.result.content[0].text' | grep -q "line1"; then
  pass "read: returns file content"
else
  fail "read: returns file content" "$READ_OK"
fi

if echo "$READ_OK" | jq -r '.result.content[0].text' | grep -qP '^\s+1\t'; then
  pass "read: cat -n format with line numbers"
else
  fail "read: cat -n format with line numbers" "$(echo "$READ_OK" | jq -r '.result.content[0].text' | head -1)"
fi

READ_NOTFOUND=$(tool_call "read" '{"path":"/workspace/nonexistent_file_xyz"}')
if echo "$READ_NOTFOUND" | jq -e '.result._meta.exit_code == 1' >/dev/null 2>&1; then
  pass "read: file not found exit_code == 1"
else
  fail "read: file not found exit_code == 1" "$(echo "$READ_NOTFOUND" | jq '.result._meta')"
fi

# ============================================================
# 6. Write tool
# ============================================================
echo ""
echo "=== Write Tool ==="
WRITE_OK=$(tool_call "write" '{"path":"/workspace/subdir/test_write.txt","content":"hello world"}')
if echo "$WRITE_OK" | jq -e '.result._meta.exit_code == 0' >/dev/null 2>&1; then
  pass "write: creates file with parent dir (exit_code 0)"
else
  fail "write: creates file with parent dir (exit_code 0)" "$(echo "$WRITE_OK" | jq '.result._meta')"
fi

# ============================================================
# 7. Edit tool
# ============================================================
echo ""
echo "=== Edit Tool ==="
tool_call "write" '{"path":"/workspace/test_edit.txt","content":"foo bar foo baz"}' >/dev/null

EDIT_OK=$(tool_call "edit" '{"path":"/workspace/test_edit.txt","old_string":"bar","new_string":"qux"}')
if echo "$EDIT_OK" | jq -e '.result._meta.exit_code == 0' >/dev/null 2>&1; then
  pass "edit: exit_code 0 on success"
else
  fail "edit: exit_code 0 on success" "$(echo "$EDIT_OK" | jq '.result._meta')"
fi

EDIT_NOTFOUND=$(tool_call "edit" '{"path":"/workspace/test_edit.txt","old_string":"zzzzz","new_string":"yyy"}')
if echo "$EDIT_NOTFOUND" | jq -e '.result._meta.exit_code == 1' >/dev/null 2>&1; then
  pass "edit: exit_code 1 string not found"
else
  fail "edit: exit_code 1 string not found" "$(echo "$EDIT_NOTFOUND" | jq '.result._meta')"
fi

EDIT_MULTI=$(tool_call "edit" '{"path":"/workspace/test_edit.txt","old_string":"foo","new_string":"xxx"}')
if echo "$EDIT_MULTI" | jq -e '.result._meta.exit_code == 2' >/dev/null 2>&1; then
  pass "edit: exit_code 2 multiple matches"
else
  fail "edit: exit_code 2 multiple matches" "$(echo "$EDIT_MULTI" | jq '.result._meta')"
fi

EDIT_NOFILE=$(tool_call "edit" '{"path":"/workspace/no_such_file.txt","old_string":"a","new_string":"b"}')
if echo "$EDIT_NOFILE" | jq -e '.result._meta.exit_code == 3' >/dev/null 2>&1; then
  pass "edit: exit_code 3 file not found"
else
  fail "edit: exit_code 3 file not found" "$(echo "$EDIT_NOFILE" | jq '.result._meta')"
fi

# ============================================================
# 8. Grep tool
# ============================================================
echo ""
echo "=== Grep Tool ==="
GREP_OK=$(tool_call "grep" '{"pattern":"hello","path":"/workspace"}')
if echo "$GREP_OK" | jq -e '.result._meta.exit_code == 0' >/dev/null 2>&1; then
  pass "grep: matches found exit_code == 0"
else
  fail "grep: matches found exit_code == 0" "$(echo "$GREP_OK" | jq '.result._meta')"
fi

GREP_NONE=$(tool_call "grep" '{"pattern":"zzz_nonexistent_pattern_zzz","path":"/workspace"}')
if echo "$GREP_NONE" | jq -e '.result._meta.exit_code == 1' >/dev/null 2>&1; then
  pass "grep: no matches exit_code == 1"
else
  fail "grep: no matches exit_code == 1" "$(echo "$GREP_NONE" | jq '.result._meta')"
fi

# ============================================================
# 9. Glob tool
# ============================================================
echo ""
echo "=== Glob Tool ==="
GLOB_OK=$(tool_call "glob" '{"pattern":"*.txt","path":"/workspace"}')
if echo "$GLOB_OK" | jq -e '.result._meta.exit_code == 0' >/dev/null 2>&1; then
  pass "glob: returns results"
else
  fail "glob: returns results" "$(echo "$GLOB_OK" | jq '.result._meta')"
fi

# ============================================================
# 10. Ls tool
# ============================================================
echo ""
echo "=== Ls Tool ==="
LS_OK=$(tool_call "ls" '{"path":"/workspace"}')
if echo "$LS_OK" | jq -e '.result._meta.exit_code == 0' >/dev/null 2>&1; then
  pass "ls: returns directory listing"
else
  fail "ls: returns directory listing" "$(echo "$LS_OK" | jq '.result._meta')"
fi

LS_NOTFOUND=$(tool_call "ls" '{"path":"/nonexistent_dir_xyz"}')
if echo "$LS_NOTFOUND" | jq -e '.result._meta.exit_code == 1' >/dev/null 2>&1; then
  pass "ls: path not found exit_code == 1"
else
  fail "ls: path not found exit_code == 1" "$(echo "$LS_NOTFOUND" | jq '.result._meta')"
fi

# ============================================================
# 11. Upload/Download round-trip
# ============================================================
echo ""
echo "=== Upload/Download ==="
# Upload binary content (base64 of "binary\x00test")
B64_CONTENT=$(echo -n "binary test content" | base64)
UPLOAD_OK=$(tool_call "upload_file" "{\"path\":\"/workspace/test_upload.bin\",\"content_base64\":\"$B64_CONTENT\"}")
if echo "$UPLOAD_OK" | jq -e '.result._meta.exit_code == 0' >/dev/null 2>&1; then
  pass "upload_file: success exit_code == 0"
else
  fail "upload_file: success exit_code == 0" "$(echo "$UPLOAD_OK" | jq '.result._meta')"
fi

DOWNLOAD_OK=$(tool_call "download_file" '{"path":"/workspace/test_upload.bin"}')
DOWNLOADED_B64=$(echo "$DOWNLOAD_OK" | jq -r '.result.content[0].text')
if [ "$DOWNLOADED_B64" = "$B64_CONTENT" ]; then
  pass "download_file: round-trip preserves content"
else
  fail "download_file: round-trip preserves content" "expected=$B64_CONTENT got=$DOWNLOADED_B64"
fi

DOWNLOAD_NOTFOUND=$(tool_call "download_file" '{"path":"/workspace/no_such_file.bin"}')
if echo "$DOWNLOAD_NOTFOUND" | jq -e '.result._meta.exit_code == 1' >/dev/null 2>&1; then
  pass "download_file: file not found exit_code == 1"
else
  fail "download_file: file not found exit_code == 1" "$(echo "$DOWNLOAD_NOTFOUND" | jq '.result._meta')"
fi

# ============================================================
# 12. Python3 and workspace
# ============================================================
echo ""
echo "=== Python3 & Workspace ==="
PY_VER=$(tool_call "execute" '{"cmd":"python3 --version"}')
if echo "$PY_VER" | jq -e '.result.content[0].text' | grep -qi "python"; then
  pass "python3 --version succeeds"
else
  fail "python3 --version succeeds" "$(echo "$PY_VER" | jq -r '.result.content[0].text')"
fi

PWD_CHECK=$(tool_call "execute" '{"cmd":"pwd"}')
if echo "$PWD_CHECK" | jq -r '.result.content[0].text' | grep -q "/workspace"; then
  pass "pwd returns /workspace"
else
  fail "pwd returns /workspace" "$(echo "$PWD_CHECK" | jq -r '.result.content[0].text')"
fi

# ============================================================
# 13. OpenClaw layout
# ============================================================
echo ""
echo "=== OpenClaw Layout ==="
for F in AGENTS.md SOUL.md USER.md IDENTITY.md TOOLS.md MEMORY.md; do
  CHECK=$(tool_call "execute" "{\"cmd\":\"test -f /workspace/$F && echo exists\"}")
  if echo "$CHECK" | jq -r '.result.content[0].text' | grep -q "exists"; then
    pass "OpenClaw file: $F exists"
  else
    fail "OpenClaw file: $F exists" "not found"
  fi
done

for D in memory skills canvas; do
  CHECK=$(tool_call "execute" "{\"cmd\":\"test -d /workspace/$D && echo exists\"}")
  if echo "$CHECK" | jq -r '.result.content[0].text' | grep -q "exists"; then
    pass "OpenClaw dir: $D/ exists"
  else
    fail "OpenClaw dir: $D/ exists" "not found"
  fi
done

# ============================================================
# 14. Session reuse and cleanup
# ============================================================
echo ""
echo "=== Session Management ==="
REUSE_RESP=$(tool_call "execute" '{"cmd":"echo reuse_test"}')
if echo "$REUSE_RESP" | jq -e '.result.content[0].text' | grep -q "reuse_test"; then
  pass "session reuse works"
else
  fail "session reuse works" "$REUSE_RESP"
fi

# Session cleanup
DEL_RESP=$(curl -s -o /dev/null -w "%{http_code}" -X DELETE "$SERVER/mcp" -H "Mcp-Session-Id: $SESSION_ID")
if [ "$DEL_RESP" = "200" ] || [ "$DEL_RESP" = "204" ]; then
  pass "DELETE /mcp closes session"
else
  fail "DELETE /mcp closes session" "HTTP $DEL_RESP"
fi

# ============================================================
# Summary
# ============================================================
echo ""
echo "=============================="
TOTAL=$((PASS+FAIL))
echo "Results: $PASS/$TOTAL passed, $FAIL failed"
echo "=============================="

if [ "$FAIL" -gt 0 ]; then
  exit 1
fi
exit 0
