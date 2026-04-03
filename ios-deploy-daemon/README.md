# iOS Deploy Daemon

A lightweight build server that lets sandboxed environments (like Copilot CLI) trigger TestFlight deploys.

## How It Works

```
┌─────────────┐     HTTP POST      ┌──────────────┐     xcodebuild      ┌───────────┐
│  Sandbox    │ ──────────────────▶ │   Daemon     │ ──────────────────▶ │ TestFlight│
│  (client)   │ ◀────────────────── │  (port 19418)│ ◀────────────────── │           │
│             │     job status      │              │     upload result   │           │
└─────────────┘                     └──────────────┘                     └───────────┘
```

The daemon runs in a normal Terminal with full Xcode access. The client runs anywhere.

## Setup (one-time)

```bash
# 1. Start the daemon from a normal Terminal
./ios-deploy-daemon/bin/daemon.sh start

# 2. Verify it's running
./ios-deploy-daemon/bin/client.sh health
```

## Deploy from Sandbox

```bash
# Submit a build
./ios-deploy-daemon/bin/client.sh request ios-deploy-daemon/config/ymoney.json

# Or wait for completion
JOB_ID=$(./ios-deploy-daemon/bin/client.sh request ios-deploy-daemon/config/ymoney.json 2>&1 | grep -oP 'deploy-[\w-]+')
./ios-deploy-daemon/bin/client.sh wait $JOB_ID
```

## Deploy from Copilot CLI

From the Copilot CLI agent, just run:
```bash
curl -s -X POST http://localhost:19418/deploy \
  -H "Content-Type: application/json" \
  -d @ios-deploy-daemon/config/ymoney.json
```

Then poll status:
```bash
curl -s http://localhost:19418/status/<job_id>
```

## API

| Method | Path | Description |
|--------|------|-------------|
| `GET` | `/health` | Health check |
| `POST` | `/deploy` | Submit a deploy job (returns job_id) |
| `GET` | `/status/:job_id` | Get job status + output |
| `GET` | `/jobs` | List recent jobs |

### POST /deploy body

```json
{
    "repo_path": "/path/to/git/repo",
    "scheme": "MyApp",
    "project": "MyApp.xcodeproj",
    "api_key_id": "KEYID",
    "api_issuer": "issuer-uuid",
    "api_key_path": "/path/to/AuthKey.p8",
    "team_id": "TEAMID",
    "bump_build": true,
    "branch": "main"
}
```

Only `repo_path`, `scheme`, `api_key_id`, `api_issuer`, `api_key_path`, and `team_id` are required. The rest is auto-detected.

## Adding a New Project

Create a config file in `config/`:

```json
{
    "repo_path": "/path/to/your/project",
    "scheme": "YourScheme",
    "api_key_id": "YOUR_KEY_ID",
    "api_issuer": "your-issuer-uuid",
    "api_key_path": "/path/to/AuthKey.p8",
    "team_id": "YOUR_TEAM_ID"
}
```

Then deploy: `./bin/client.sh request config/yourproject.json`
