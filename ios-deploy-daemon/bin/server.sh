#!/bin/bash
set -euo pipefail

# HTTP server using bash + netcat
# This is the core server loop that handles requests.

PORT="${1:-19418}"
DAEMON_DIR="$(cd "$(dirname "$0")/.." && pwd)"
JOBS_DIR="$DAEMON_DIR/logs/jobs"
mkdir -p "$JOBS_DIR"

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"; }

respond() {
    local status="$1" content_type="$2" body="$3"
    local length=${#body}
    printf "HTTP/1.1 %s\r\nContent-Type: %s\r\nContent-Length: %d\r\nConnection: close\r\n\r\n%s" \
        "$status" "$content_type" "$length" "$body"
}

respond_json() {
    respond "$1" "application/json" "$2"
}

handle_request() {
    local method path body=""
    
    # Read request line
    read -r line
    method=$(echo "$line" | awk '{print $1}')
    path=$(echo "$line" | awk '{print $2}')
    
    # Read headers, find Content-Length
    local content_length=0
    while read -r header; do
        header=$(echo "$header" | tr -d '\r')
        [[ -z "$header" ]] && break
        if [[ "$header" =~ ^[Cc]ontent-[Ll]ength:\ *([0-9]+) ]]; then
            content_length="${BASH_REMATCH[1]}"
        fi
    done
    
    # Read body if present
    if [[ "$content_length" -gt 0 ]]; then
        body=$(dd bs=1 count="$content_length" 2>/dev/null)
    fi
    
    log "$method $path"
    
    # Route requests
    case "$method $path" in
        "GET /health")
            respond_json "200 OK" '{"status":"ok","service":"ios-deploy-daemon"}'
            ;;
        "POST /deploy")
            handle_deploy "$body"
            ;;
        "GET /status/"*)
            local job_id="${path#/status/}"
            handle_status "$job_id"
            ;;
        "GET /jobs")
            handle_list_jobs
            ;;
        *)
            respond_json "404 Not Found" '{"error":"not found"}'
            ;;
    esac
}

handle_deploy() {
    local body="$1"
    
    # Parse JSON fields using python (available on macOS)
    local repo_path scheme project workspace api_key_id api_issuer api_key_path team_id bump_build branch
    repo_path=$(echo "$body" | python3 -c "import sys,json; print(json.load(sys.stdin).get('repo_path',''))" 2>/dev/null)
    scheme=$(echo "$body" | python3 -c "import sys,json; print(json.load(sys.stdin).get('scheme',''))" 2>/dev/null)
    project=$(echo "$body" | python3 -c "import sys,json; print(json.load(sys.stdin).get('project',''))" 2>/dev/null)
    workspace=$(echo "$body" | python3 -c "import sys,json; print(json.load(sys.stdin).get('workspace',''))" 2>/dev/null)
    api_key_id=$(echo "$body" | python3 -c "import sys,json; print(json.load(sys.stdin).get('api_key_id',''))" 2>/dev/null)
    api_issuer=$(echo "$body" | python3 -c "import sys,json; print(json.load(sys.stdin).get('api_issuer',''))" 2>/dev/null)
    api_key_path=$(echo "$body" | python3 -c "import sys,json; print(json.load(sys.stdin).get('api_key_path',''))" 2>/dev/null)
    team_id=$(echo "$body" | python3 -c "import sys,json; print(json.load(sys.stdin).get('team_id',''))" 2>/dev/null)
    bump_build=$(echo "$body" | python3 -c "import sys,json; print(json.load(sys.stdin).get('bump_build',False))" 2>/dev/null)
    branch=$(echo "$body" | python3 -c "import sys,json; print(json.load(sys.stdin).get('branch',''))" 2>/dev/null)
    
    # Validate required fields
    if [[ -z "$repo_path" || -z "$scheme" || -z "$api_key_id" || -z "$api_issuer" || -z "$api_key_path" || -z "$team_id" ]]; then
        respond_json "400 Bad Request" '{"error":"Missing required fields: repo_path, scheme, api_key_id, api_issuer, api_key_path, team_id"}'
        return
    fi
    
    if [[ ! -d "$repo_path" ]]; then
        respond_json "400 Bad Request" "{\"error\":\"repo_path not found: $repo_path\"}"
        return
    fi
    
    if [[ ! -f "$api_key_path" ]]; then
        respond_json "400 Bad Request" "{\"error\":\"api_key_path not found: $api_key_path\"}"
        return
    fi
    
    # Generate job ID
    local job_id
    job_id="deploy-$(date +%Y%m%d-%H%M%S)-$$"
    local job_dir="$JOBS_DIR/$job_id"
    mkdir -p "$job_dir"
    
    # Write job config
    echo "$body" > "$job_dir/request.json"
    echo "queued" > "$job_dir/status"
    date '+%Y-%m-%d %H:%M:%S' > "$job_dir/started"
    
    # Run build in background
    (
        "$DAEMON_DIR/bin/build.sh" \
            "$repo_path" "$scheme" "$project" "$workspace" \
            "$api_key_id" "$api_issuer" "$api_key_path" "$team_id" \
            "$bump_build" "$branch" \
            > "$job_dir/output.log" 2>&1
        
        if [[ $? -eq 0 ]]; then
            echo "succeeded" > "$job_dir/status"
        else
            echo "failed" > "$job_dir/status"
        fi
        date '+%Y-%m-%d %H:%M:%S' > "$job_dir/finished"
    ) &
    
    echo "running" > "$job_dir/status"
    
    respond_json "202 Accepted" "{\"job_id\":\"$job_id\",\"status\":\"running\"}"
}

handle_status() {
    local job_id="$1"
    local job_dir="$JOBS_DIR/$job_id"
    
    if [[ ! -d "$job_dir" ]]; then
        respond_json "404 Not Found" "{\"error\":\"job not found: $job_id\"}"
        return
    fi
    
    local status started finished output
    status=$(cat "$job_dir/status" 2>/dev/null || echo "unknown")
    started=$(cat "$job_dir/started" 2>/dev/null || echo "")
    finished=$(cat "$job_dir/finished" 2>/dev/null || echo "")
    # Last 50 lines of output
    output=$(tail -50 "$job_dir/output.log" 2>/dev/null | python3 -c "import sys,json; print(json.dumps(sys.stdin.read()))" 2>/dev/null || echo '""')
    
    respond_json "200 OK" "{\"job_id\":\"$job_id\",\"status\":\"$status\",\"started\":\"$started\",\"finished\":\"$finished\",\"output\":$output}"
}

handle_list_jobs() {
    local jobs="[]"
    if [[ -d "$JOBS_DIR" ]]; then
        jobs=$(ls -1t "$JOBS_DIR" 2>/dev/null | head -20 | while read -r jid; do
            local st=$(cat "$JOBS_DIR/$jid/status" 2>/dev/null || echo "unknown")
            echo "{\"job_id\":\"$jid\",\"status\":\"$st\"}"
        done | python3 -c "import sys,json; print(json.dumps([json.loads(l) for l in sys.stdin]))" 2>/dev/null || echo "[]")
    fi
    respond_json "200 OK" "{\"jobs\":$jobs}"
}

# Main server loop
log "iOS Deploy Daemon listening on port $PORT"
while true; do
    handle_request | nc -l "$PORT" > /dev/null
done
