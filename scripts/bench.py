#!/usr/bin/env python3
"""Paired cold/warm client-side timings on the local emulator."""
import json
import os
from pathlib import Path
import statistics
import shlex
import subprocess
import sys
import tempfile
import time
import urllib.parse

root = Path(__file__).resolve().parent.parent
count = int(sys.argv[1]) if len(sys.argv) > 1 else 10
function = sys.argv[2] if len(sys.argv) > 2 else os.environ["WEBHOOK_FN"]
fixtures = {os.environ["WEBHOOK_FN"]: "events/valid.json", os.environ["READER_FN"]: "events/reader/valid.json"}
if not 1 <= count <= 100 or function not in fixtures:
    raise SystemExit("Use 1..100 pairs and the webhook or reader function name")
endpoint = os.environ["AWS_ENDPOINT_URL"]
if urllib.parse.urlparse(endpoint).hostname not in ("localhost", "127.0.0.1"):
    raise SystemExit("Only local Floci is supported")
evidence = Path(os.environ["LESSON12_EVIDENCE_DIR"]).resolve()
if evidence == root or root in evidence.parents:
    raise SystemExit("Evidence directory must be outside the repository")
logs = evidence / "logs"
logs.mkdir(parents=True, exist_ok=True)
pairs = []


def docker(*args):
    command = ["docker", *args]
    wrapper = os.environ.get("LESSON12_DOCKER_WRAPPER")
    if wrapper:
        command = [wrapper, shlex.join(command)]
    return subprocess.run(command, capture_output=True, text=True, check=True)


network_data = json.loads(docker("inspect", "lesson12-floci", "--format", "{{json .NetworkSettings.Networks}}").stdout)
if len(network_data) != 1:
    raise SystemExit("Expected one isolated Compose network for lesson12-floci")
network = next(iter(network_data))

with tempfile.TemporaryDirectory(dir=logs) as tmp:
    response = Path(tmp) / "invoke.json"

    def invoke():
        start = time.perf_counter()
        result = subprocess.run(["aws", "--endpoint-url", endpoint, "--no-cli-pager", "lambda", "invoke",
                                 "--function-name", function, "--payload", "fileb://" + str(root / fixtures[function]),
                                 str(response)], capture_output=True, text=True, check=True)
        elapsed = (time.perf_counter() - start) * 1000
        meta = json.loads(result.stdout)
        body = json.loads(response.read_text())
        if meta.get("FunctionError") or body.get("statusCode") != 200:
            raise RuntimeError("Failed invocation cannot be used as a timing sample: " + response.read_text())
        return elapsed

    invoke()  # Downloaded images and CLI initialization are outside the pairs.
    for i in range(count):
        # Anchor the actual Floci-generated name so unrelated containers are untouched.
        result = docker("ps", "-aq", "--filter", f"name=-{function}-", "--filter", f"network={network}")
        ids = result.stdout.split()
        if not ids:
            raise RuntimeError("No warm Floci container found; cannot establish a cold invocation")
        docker("rm", "-f", *ids)
        cold, warm = invoke(), invoke()
        pairs.append({"cold_ms": round(cold, 2), "warm_ms": round(warm, 2)})
        print(f"#{i+1:02} cold={cold:.2f} ms warm={warm:.2f} ms", flush=True)

summary = {"function": function, "pairs": pairs, "measurement": "client elapsed time, including AWS CLI and local HTTP"}
for key in ("cold_ms", "warm_ms"):
    values = [pair[key] for pair in pairs]
    summary[key] = {"mean": round(statistics.mean(values), 2), "median": round(statistics.median(values), 2),
                    "min": min(values), "max": max(values)}
    print(key, summary[key])
(logs / "cold-warm.json").write_text(json.dumps(summary, indent=2))
print("Local Docker container startup and CLI/HTTP overhead are included. These are not AWS Init Duration measurements.")
