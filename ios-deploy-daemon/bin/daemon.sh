#!/bin/bash
set -euo pipefail

# iOS Deploy Daemon
# A lightweight HTTP server that accepts build+deploy requests from sandboxed environments.
#
# Usage:
#   ./ios-deploy-daemon/bin/daemon.sh start   # Start the daemon (port 19418)
#   ./ios-deploy-daemon/bin/daemon.sh stop    # Stop the daemon
#   ./ios-deploy-daemon/bin/daemon.sh status  # Check if running
#
# API:
#   POST /deploy  — Build and upload to TestFlight
#     Body (JSON): {
#       "repo_path": "/path/to/git/repo",
#       "scheme": "MyApp",
#       "project": "MyApp.xcodeproj",   (optional, auto-detected)
#       "workspace": "MyApp.xcworkspace", (optional, use instead of project)
#       "api_key_id": "KEYID",
#       "api_issuer": "issuer-uuid",
#       "api_key_path": "/path/to/AuthKey.p8",
#       "team_id": "TEAMID",
#       "bump_build": true,              (optional)
#       "branch": "main"                 (optional, builds current HEAD if omitted)
#     }
#
#   GET /status/:job_id  — Check build status
#   GET /health          — Health check
#
# The daemon runs outside any sandbox with full access to Xcode services,
# keychain, and signing certificates.

DAEMON_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PID_FILE="$DAEMON_DIR/logs/daemon.pid"
LOG_FILE="$DAEMON_DIR/logs/daemon.log"
PORT="${IOS_DEPLOY_PORT:-19418}"

case "${1:-start}" in
    start)
        if [[ -f "$PID_FILE" ]] && kill -0 "$(cat "$PID_FILE")" 2>/dev/null; then
            echo "Daemon already running (PID $(cat "$PID_FILE")) on port $PORT"
            exit 0
        fi
        echo "Starting iOS Deploy Daemon on port $PORT..."
        nohup python3 "$DAEMON_DIR/bin/server.py" >> "$LOG_FILE" 2>&1 &
        echo $! > "$PID_FILE"
        echo "Started (PID $!, log: $LOG_FILE)"
        ;;
    stop)
        if [[ -f "$PID_FILE" ]]; then
            PID=$(cat "$PID_FILE")
            kill "$PID" 2>/dev/null && echo "Stopped (PID $PID)" || echo "Not running"
            rm -f "$PID_FILE"
        else
            echo "Not running"
        fi
        ;;
    status)
        if [[ -f "$PID_FILE" ]] && kill -0 "$(cat "$PID_FILE")" 2>/dev/null; then
            echo "Running (PID $(cat "$PID_FILE")) on port $PORT"
        else
            echo "Not running"
            rm -f "$PID_FILE" 2>/dev/null
        fi
        ;;
    *)
        echo "Usage: $0 {start|stop|status}"
        exit 1
        ;;
esac
