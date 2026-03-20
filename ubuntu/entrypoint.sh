#!/bin/sh

# Create OpenClaw workspace layout (as executor user)
su -s /bin/sh executor -c '
  mkdir -p /workspace/memory /workspace/skills /workspace/canvas
  for f in AGENTS.md SOUL.md USER.md IDENTITY.md TOOLS.md MEMORY.md; do
    [ -f "/workspace/$f" ] || touch "/workspace/$f"
  done
'

exec node /app/index.js
