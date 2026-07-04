#!/bin/bash
# Launch GDB-patched FS-UAE with A1200 kickstart.
# GDB server listens on localhost:2345 (waits up to 200s for connection,
# then boots normally). One GDB session per launch — server closes on
# client disconnect.
set -e
PROJECT="$(cd "$(dirname "$0")/.." && pwd)"
exec "$PROJECT/tools/fs-uae-gdb/fs-uae-darwin_x64" \
  --amiga_model=A1200 \
  "--kickstart_file=$PROJECT/kickstart/Kickstart v3.1 rev 40.68 (1993)(Commodore)(A1200).rom" \
  --fast_memory=4096 \
  --floppy_drive_speed=0 \
  --remote_debugger=200 \
  --remote_debugger_port=2345 \
  "$@"
