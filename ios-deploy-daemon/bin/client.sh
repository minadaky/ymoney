#!/bin/bash
set -euo pipefail

# iOS Deploy Client
# Sends build requests to the deploy daemon from sandboxed environments.
#
# Usage:
#   ios-deploy request <config.json>     # Submit a deploy job
#   ios-deploy status <job_id>           # Check job status
#   ios-deploy wait <job_id>             # Wait for job to complete
#   ios-deploy jobs                      # List recent jobs
#   ios-deploy health                    # Health check
#
# Environment:
#   IOS_DEPLOY_HOST  — daemon host (default: localhost)
#   IOS_DEPLOY_PORT  — daemon port (default: 19418)

HOST="${IOS_DEPLOY_HOST:-localhost}"
PORT="${IOS_DEPLOY_PORT:-19418}"
BASE_URL="http://${HOST}:${PORT}"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

case "${1:-help}" in
    request|deploy)
        CONFIG="${2:-}"
        if [[ -z "$CONFIG" ]]; then
            echo "Usage: $0 request <config.json or inline JSON>"
            exit 1
        fi
        
        # Accept file path or inline JSON
        if [[ -f "$CONFIG" ]]; then
            BODY=$(cat "$CONFIG")
        else
            BODY="$CONFIG"
        fi
        
        echo -e "${CYAN}▸${NC} Submitting deploy request..."
        RESPONSE=$(curl -s -X POST "${BASE_URL}/deploy" \
            -H "Content-Type: application/json" \
            -d "$BODY")
        
        JOB_ID=$(echo "$RESPONSE" | python3 -c "import sys,json; print(json.load(sys.stdin).get('job_id',''))" 2>/dev/null)
        STATUS=$(echo "$RESPONSE" | python3 -c "import sys,json; print(json.load(sys.stdin).get('status',''))" 2>/dev/null)
        ERROR=$(echo "$RESPONSE" | python3 -c "import sys,json; print(json.load(sys.stdin).get('error',''))" 2>/dev/null)
        
        if [[ -n "$ERROR" && "$ERROR" != "None" ]]; then
            echo -e "${RED}✗${NC} Error: $ERROR"
            exit 1
        fi
        
        echo -e "${GREEN}▸${NC} Job submitted: $JOB_ID (status: $STATUS)"
        echo -e "${CYAN}▸${NC} Track with: $0 wait $JOB_ID"
        ;;
    
    status)
        JOB_ID="${2:?Usage: $0 status <job_id>}"
        RESPONSE=$(curl -s "${BASE_URL}/status/${JOB_ID}")
        
        STATUS=$(echo "$RESPONSE" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('status','unknown'))" 2>/dev/null)
        STARTED=$(echo "$RESPONSE" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('started',''))" 2>/dev/null)
        FINISHED=$(echo "$RESPONSE" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('finished',''))" 2>/dev/null)
        
        case "$STATUS" in
            running)   echo -e "${YELLOW}▸${NC} $JOB_ID: running (started: $STARTED)" ;;
            succeeded) echo -e "${GREEN}✓${NC} $JOB_ID: succeeded (finished: $FINISHED)" ;;
            failed)    echo -e "${RED}✗${NC} $JOB_ID: failed (finished: $FINISHED)" ;;
            *)         echo -e "${CYAN}▸${NC} $JOB_ID: $STATUS" ;;
        esac
        
        # Show last few lines of output
        OUTPUT=$(echo "$RESPONSE" | python3 -c "import sys,json; print(json.load(sys.stdin).get('output',''))" 2>/dev/null)
        if [[ -n "$OUTPUT" && "$OUTPUT" != "None" ]]; then
            echo ""
            echo "$OUTPUT" | tail -10
        fi
        ;;
    
    wait)
        JOB_ID="${2:?Usage: $0 wait <job_id>}"
        echo -e "${CYAN}▸${NC} Waiting for $JOB_ID..."
        
        while true; do
            RESPONSE=$(curl -s "${BASE_URL}/status/${JOB_ID}")
            STATUS=$(echo "$RESPONSE" | python3 -c "import sys,json; print(json.load(sys.stdin).get('status','unknown'))" 2>/dev/null)
            
            case "$STATUS" in
                succeeded)
                    echo -e "\n${GREEN}✓${NC} Deploy succeeded!"
                    OUTPUT=$(echo "$RESPONSE" | python3 -c "import sys,json; print(json.load(sys.stdin).get('output',''))" 2>/dev/null)
                    echo "$OUTPUT" | grep -E '(succeeded|TestFlight|Upload)' || true
                    exit 0
                    ;;
                failed)
                    echo -e "\n${RED}✗${NC} Deploy failed!"
                    OUTPUT=$(echo "$RESPONSE" | python3 -c "import sys,json; print(json.load(sys.stdin).get('output',''))" 2>/dev/null)
                    echo "$OUTPUT" | tail -20
                    exit 1
                    ;;
                running|queued)
                    printf "."
                    sleep 10
                    ;;
                *)
                    echo -e "\n${RED}✗${NC} Unknown status: $STATUS"
                    exit 1
                    ;;
            esac
        done
        ;;
    
    jobs)
        curl -s "${BASE_URL}/jobs" | python3 -c "
import sys, json
data = json.load(sys.stdin)
for j in data.get('jobs', []):
    status = j['status']
    icon = '✓' if status == 'succeeded' else '✗' if status == 'failed' else '…'
    print(f'  {icon} {j[\"job_id\"]:40s} {status}')
" 2>/dev/null || echo "Failed to connect to daemon"
        ;;
    
    health)
        RESPONSE=$(curl -s --max-time 3 "${BASE_URL}/health" 2>/dev/null || echo "")
        if [[ "$RESPONSE" == *'"ok"'* ]]; then
            echo -e "${GREEN}✓${NC} Daemon is running on ${HOST}:${PORT}"
        else
            echo -e "${RED}✗${NC} Daemon not reachable at ${HOST}:${PORT}"
            exit 1
        fi
        ;;
    
    help|*)
        echo "iOS Deploy Client — submit builds to the deploy daemon"
        echo ""
        echo "Usage:"
        echo "  $0 request <config.json>   Submit a deploy job"
        echo "  $0 status <job_id>         Check job status"
        echo "  $0 wait <job_id>           Wait for completion"
        echo "  $0 jobs                    List recent jobs"
        echo "  $0 health                  Health check"
        echo ""
        echo "Quick deploy example:"
        echo "  $0 request '{\"repo_path\":\"/path/to/repo\",\"scheme\":\"MyApp\",\"api_key_id\":\"KEY\",\"api_issuer\":\"UUID\",\"api_key_path\":\"/path/to/key.p8\",\"team_id\":\"TEAM\"}'"
        ;;
esac
