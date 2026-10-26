#!/usr/bin/env python3
"""Exercise real local Lambda/API Gateway/S3; keep responses outside the repo."""
import hashlib
import json
import os
from pathlib import Path
import struct
import subprocess
import time
import urllib.error
import urllib.parse
import urllib.request
import uuid

ROOT = Path(__file__).resolve().parent.parent
ENDPOINT = os.environ.get("AWS_ENDPOINT_URL", "http://localhost:4566").rstrip("/")
parsed = urllib.parse.urlparse(ENDPOINT)
if parsed.scheme != "http" or parsed.hostname not in ("localhost", "127.0.0.1"):
    raise SystemExit("Smoke tests support a local Floci endpoint only")
evidence = Path(os.environ.get("LESSON12_EVIDENCE_DIR", ROOT.parent / "lesson12-evidence")).resolve()
if evidence == ROOT or ROOT in evidence.parents:
    raise SystemExit("Evidence directory must be outside the repository")
OUT = evidence / "logs" / ("smoke-" + uuid.uuid4().hex[:8])
OUT.mkdir(parents=True)
results = []


def aws(*args):
    command = ["aws", "--endpoint-url", ENDPOINT, "--no-cli-pager",
               "--cli-connect-timeout", "5", "--cli-read-timeout", "60", *map(str, args)]
    result = subprocess.run(command, capture_output=True, text=True, check=True)
    return json.loads(result.stdout) if result.stdout.strip() else None


def check(name, condition):
    results.append({"check": name, "passed": bool(condition)})
    print(("PASS " if condition else "FAIL ") + name, flush=True)


def invoke(function, event, name):
    target = OUT / (name + ".json")
    meta = aws("lambda", "invoke", "--function-name", function,
               "--payload", "fileb://" + str(event), target)
    if meta.get("FunctionError"):
        raise RuntimeError(f"Lambda invocation failed: {target.read_text()}")
    return json.loads(target.read_text())


def http(url, payload, name):
    req = urllib.request.Request(url, data=payload.read_bytes(),
                                 headers={"Content-Type": "application/json"}, method="POST")
    try:
        with urllib.request.urlopen(req, timeout=60) as resp:
            status, raw = resp.status, resp.read()
    except urllib.error.HTTPError as err:
        status, raw = err.code, err.read()
    body = json.loads(raw)
    (OUT / (name + ".json")).write_text(json.dumps({"status": status, "body": body}, ensure_ascii=False, indent=2))
    return status, body


def main():
    apis = aws("apigateway", "get-rest-apis")["items"]
    api = next(api for api in apis if api["name"] == os.environ["API_NAME"])
    base = f"{ENDPOINT}/restapis/{api['id']}/{os.environ['STAGE']}/_user_request_"
    print("API:", base, flush=True)
    for fixture, status in [("valid", 200), ("invalid", 400), ("missing_field", 400), ("unsupported_event", 400)]:
        resp = invoke(os.environ["WEBHOOK_FN"], ROOT / "events" / (fixture + ".json"), "webhook-invoke-" + fixture)
        check("webhook invoke " + fixture, resp["statusCode"] == status)
    for fixture, status in [("valid", 200), ("invalid", 400), ("malformed", 400)]:
        resp = invoke(os.environ["READER_FN"], ROOT / "events/reader" / (fixture + ".json"), "reader-invoke-" + fixture)
        check("reader invoke " + fixture, resp["statusCode"] == status)
    for fixture, status in [("valid", 200), ("malformed", 400), ("missing_field", 400)]:
        actual, body = http(base + "/webhook", ROOT / "events" / ("payload_" + fixture + ".json"), "webhook-http-" + fixture)
        check("webhook HTTP " + fixture, actual == status)
        if fixture == "valid":
            check("webhook normalized ISBN", body["donation"]["isbn"] == "9780134190440")
    for fixture, status in [("valid", 200), ("invalid", 400), ("malformed", 400)]:
        actual, body = http(base + "/readers/normalize", ROOT / "events/reader" / ("payload_" + fixture + ".json"), "reader-http-" + fixture)
        check("reader HTTP " + fixture, actual == status)
        if fixture == "valid":
            check("reader normalized profile", body["reader"] == {"name": "Олена Коваль", "email": "Reader@example.com"})

    # A unique key proves this run's upload triggered processing, not an older artifact.
    key = "covers/smoke-" + uuid.uuid4().hex[:8] + "/cover.png"
    out_key = "thumbs/" + key
    aws("s3api", "put-object", "--bucket", os.environ["COVERS_BUCKET"], "--key", key,
        "--body", ROOT / "testdata/cover.png", "--content-type", "image/png")
    target = OUT / "thumbnail.png"
    deadline = time.monotonic() + 45
    while True:
        try:
            aws("s3api", "get-object", "--bucket", os.environ["THUMBS_BUCKET"], "--key", out_key, target)
            break
        except subprocess.CalledProcessError:
            if time.monotonic() >= deadline:
                check("automatic S3 trigger (no manual fallback)", False)
                return
            time.sleep(1)
    check("automatic S3 trigger (no manual fallback)", True)
    raw = target.read_bytes()
    dimensions = struct.unpack(">II", raw[16:24]) if raw[:8] == b"\x89PNG\r\n\x1a\n" else None
    check("thumbnail is 133 x 200 PNG", dimensions == (133, 200))
    event = json.loads((ROOT / "events/s3_put.json").read_text())
    event["Records"][0]["s3"]["object"]["key"] = key
    event_file = OUT / "s3-repeat-event.json"
    event_file.write_text(json.dumps(event))
    invoke(os.environ["THUMB_FN"], event_file, "thumbnail-repeat-invoke")
    aws("s3api", "get-object", "--bucket", os.environ["THUMBS_BUCKET"], "--key", out_key, target)
    check("repeat S3 event gives identical bytes", hashlib.sha256(raw).digest() == hashlib.sha256(target.read_bytes()).digest())


try:
    main()
except Exception as err:
    check("integration execution: " + str(err), False)
finally:
    (OUT / "summary.json").write_text(json.dumps(results, ensure_ascii=False, indent=2))
    passed = sum(item["passed"] for item in results)
    print(f"PASS={passed} FAIL={len(results)-passed}; responses: {OUT}", flush=True)
raise SystemExit(0 if results and all(item["passed"] for item in results) else 1)
