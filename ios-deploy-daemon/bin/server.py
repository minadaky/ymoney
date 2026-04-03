#!/usr/bin/env python3
"""iOS Deploy Daemon — HTTP server for triggering TestFlight builds."""

import http.server
import json
import os
import subprocess
import threading
import sys
from datetime import datetime
from pathlib import Path

PORT = int(os.environ.get("IOS_DEPLOY_PORT", 19418))
DAEMON_DIR = Path(__file__).resolve().parent.parent
JOBS_DIR = DAEMON_DIR / "logs" / "jobs"
BUILD_SCRIPT = DAEMON_DIR / "bin" / "build.sh"

JOBS_DIR.mkdir(parents=True, exist_ok=True)


def log(msg):
    print(f"[{datetime.now():%Y-%m-%d %H:%M:%S}] {msg}", flush=True)


class DeployHandler(http.server.BaseHTTPRequestHandler):
    def log_message(self, format, *args):
        log(f"{self.client_address[0]} {format % args}")

    def _respond(self, code, body):
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        data = json.dumps(body).encode()
        self.send_header("Content-Length", len(data))
        self.end_headers()
        self.wfile.write(data)

    def do_GET(self):
        if self.path == "/health":
            self._respond(200, {"status": "ok", "service": "ios-deploy-daemon"})

        elif self.path.startswith("/status/"):
            job_id = self.path[len("/status/"):]
            self._handle_status(job_id)

        elif self.path == "/jobs":
            self._handle_list_jobs()

        else:
            self._respond(404, {"error": "not found"})

    def do_POST(self):
        if self.path == "/deploy":
            length = int(self.headers.get("Content-Length", 0))
            body = self.rfile.read(length).decode() if length else "{}"
            self._handle_deploy(body)
        else:
            self._respond(404, {"error": "not found"})

    def _handle_deploy(self, body):
        try:
            config = json.loads(body)
        except json.JSONDecodeError as e:
            self._respond(400, {"error": f"Invalid JSON: {e}"})
            return

        required = ["repo_path", "scheme", "api_key_id", "api_issuer", "api_key_path", "team_id"]
        missing = [f for f in required if not config.get(f)]
        if missing:
            self._respond(400, {"error": f"Missing required fields: {', '.join(missing)}"})
            return

        if not os.path.isdir(config["repo_path"]):
            self._respond(400, {"error": f"repo_path not found: {config['repo_path']}"})
            return

        if not os.path.isfile(config["api_key_path"]):
            self._respond(400, {"error": f"api_key_path not found: {config['api_key_path']}"})
            return

        # Create job
        job_id = f"deploy-{datetime.now():%Y%m%d-%H%M%S}-{os.getpid()}"
        job_dir = JOBS_DIR / job_id
        job_dir.mkdir(parents=True)

        (job_dir / "request.json").write_text(json.dumps(config, indent=2))
        (job_dir / "status").write_text("running")
        (job_dir / "started").write_text(f"{datetime.now():%Y-%m-%d %H:%M:%S}")

        # Run build in background thread
        thread = threading.Thread(target=self._run_build, args=(job_id, config), daemon=True)
        thread.start()

        self._respond(202, {"job_id": job_id, "status": "running"})

    def _run_build(self, job_id, config):
        job_dir = JOBS_DIR / job_id
        log_file = job_dir / "output.log"

        cmd = [
            str(BUILD_SCRIPT),
            config["repo_path"],
            config["scheme"],
            config.get("project", ""),
            config.get("workspace", ""),
            config["api_key_id"],
            config["api_issuer"],
            config["api_key_path"],
            config["team_id"],
            str(config.get("bump_build", False)),
            config.get("branch", ""),
        ]

        log(f"Job {job_id}: starting build for {config['scheme']}")

        try:
            with open(log_file, "w") as f:
                result = subprocess.run(cmd, stdout=f, stderr=subprocess.STDOUT, timeout=1800)

            status = "succeeded" if result.returncode == 0 else "failed"
        except subprocess.TimeoutExpired:
            status = "failed"
            with open(log_file, "a") as f:
                f.write("\n\nERROR: Build timed out after 30 minutes\n")
        except Exception as e:
            status = "failed"
            with open(log_file, "a") as f:
                f.write(f"\n\nERROR: {e}\n")

        (job_dir / "status").write_text(status)
        (job_dir / "finished").write_text(f"{datetime.now():%Y-%m-%d %H:%M:%S}")
        log(f"Job {job_id}: {status}")

    def _handle_status(self, job_id):
        job_dir = JOBS_DIR / job_id
        if not job_dir.exists():
            self._respond(404, {"error": f"job not found: {job_id}"})
            return

        status = (job_dir / "status").read_text().strip() if (job_dir / "status").exists() else "unknown"
        started = (job_dir / "started").read_text().strip() if (job_dir / "started").exists() else ""
        finished = (job_dir / "finished").read_text().strip() if (job_dir / "finished").exists() else ""

        output = ""
        log_file = job_dir / "output.log"
        if log_file.exists():
            lines = log_file.read_text().splitlines()
            output = "\n".join(lines[-50:])

        self._respond(200, {
            "job_id": job_id,
            "status": status,
            "started": started,
            "finished": finished,
            "output": output,
        })

    def _handle_list_jobs(self):
        jobs = []
        if JOBS_DIR.exists():
            for d in sorted(JOBS_DIR.iterdir(), reverse=True)[:20]:
                if d.is_dir():
                    status = (d / "status").read_text().strip() if (d / "status").exists() else "unknown"
                    jobs.append({"job_id": d.name, "status": status})
        self._respond(200, {"jobs": jobs})


def main():
    server = http.server.HTTPServer(("0.0.0.0", PORT), DeployHandler)
    log(f"iOS Deploy Daemon listening on port {PORT}")
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        log("Shutting down")
        server.server_close()


if __name__ == "__main__":
    main()
