"""Public-entry smoke tests with endpoint-specific mock fixtures (no live traffic)."""

import argparse
import gzip
import json
import os
from pathlib import Path
import subprocess
import tempfile
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen


def run(binary: str, adapter_port: int, mock_port: int) -> None:
    lock = threading.Lock()
    records = []
    statuses = {"/batch": [], "/flags": []}
    flags = {}

    class MockHandler(BaseHTTPRequestHandler):
        def log_message(self, *args):
            pass

        def do_GET(self):
            self.send_response(404)
            self.end_headers()

        def do_POST(self):
            raw = self.rfile.read(int(self.headers.get("Content-Length", 0)))
            if self.headers.get("Content-Encoding") == "gzip":
                raw = gzip.decompress(raw)
            path = self.path.split("?")[0].rstrip("/")
            body = json.loads(raw)
            with lock:
                queue = statuses.get(path, [])
                status = queue.pop(0) if queue else 200
                records.append((path, status, body))
                response = {"featureFlags": flags.copy(), "featureFlagPayloads": {}} if path == "/flags" else {"status": 1}
            encoded = json.dumps(response).encode()
            self.send_response(status)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(encoded)))
            self.end_headers()
            self.wfile.write(encoded)

    # Binding fails rather than reusing another process's mock port.
    mock = ThreadingHTTPServer(("127.0.0.1", mock_port), MockHandler)
    thread = threading.Thread(target=mock.serve_forever, daemon=True)
    thread.start()
    base_url = f"http://127.0.0.1:{adapter_port}"

    def call(path, body=None):
        data = json.dumps(body).encode() if body is not None else None
        request = Request(base_url + path, data=data, headers={"Content-Type": "application/json"})
        with urlopen(request, timeout=35) as response:
            return json.load(response)

    def initialize():
        call("/reset", {})
        with lock:
            records.clear()
            statuses["/batch"] = []
            statuses["/flags"] = []
            flags.clear()
        call("/init", {"api_key": "phc_local_smoke", "host": f"http://127.0.0.1:{mock_port}",
                       "flush_at": 10, "flush_interval_ms": 500, "max_retries": 3})

    with tempfile.TemporaryDirectory(prefix="posthog-adapter-smoke-") as home:
        env = dict(os.environ, TMPDIR=home + "/")
        # Refuse to attach tests to an unrelated adapter already using the requested port.
        import socket
        with socket.socket() as probe:
            probe.bind(("127.0.0.1", adapter_port))
        with open(Path(home) / "adapter.log", "w+") as log:
            process = subprocess.Popen([binary, "serve", "--hostname", "127.0.0.1", "--port", str(adapter_port)],
                                       env=env, stdout=log, stderr=subprocess.STDOUT)
            try:
                for _ in range(100):
                    if process.poll() is not None:
                        raise RuntimeError("Adapter exited during startup")
                    try:
                        call("/health")
                        break
                    except URLError:
                        time.sleep(0.1)
                else:
                    raise RuntimeError("Adapter did not become healthy")

                initialize()
                with lock:
                    statuses["/batch"] = [503, 200]
                capture = call("/capture", {"event": "timestamp-smoke", "distinct_id": "user",
                                           "timestamp": "2025-01-02T08:34:05+05:30",
                                           "properties": {"literal": "2025-01-02T08:34:05+05:30"}})
                assert capture["success"] and capture["uuid"]
                flushed = call("/flush", {})
                assert flushed == {"success": True, "events_flushed": 1}, flushed
                observation = call("/state")
                assert observation["pending_events"] == 0, observation
                assert observation["total_retries"] == 1, observation
                with lock:
                    uploads = [r for r in records if r[0] == "/batch"]
                assert [r[1] for r in uploads] == [503, 200], uploads
                first, second = [r[2]["batch"][0] for r in uploads]
                assert first["uuid"] == second["uuid"] == capture["uuid"]
                assert first["timestamp"] == second["timestamp"] == "2025-01-02T03:04:05.000Z"
                assert first["properties"]["literal"] == "2025-01-02T08:34:05+05:30"
                print("PASS capture Date forwarding, UUID response, genuine 503 retry and flush acknowledgment")
                try:
                    call("/capture", {"event": "bad-timestamp", "timestamp": "invalid"})
                    raise AssertionError("Invalid timestamp accepted")
                except HTTPError as error:
                    assert error.code == 400
                print("PASS invalid capture timestamp rejects before enqueue")

                for status in [502, 504]:
                    initialize()
                    with lock:
                        statuses["/flags"] = [status, 200]
                        flags["smoke-flag"] = "variant-a"
                    result = call("/get_feature_flag", {"key": "smoke-flag", "distinct_id": "user",
                                                       "person_properties": {"plan": "paid"},
                                                       "groups": {"company": "acme"},
                                                       "group_properties": {"company": {"plan": "enterprise"}},
                                                       "force_remote": True})
                    assert result["value"] == "variant-a", result
                    call("/flush", {})
                    with lock:
                        requests = list(records)
                    flag_requests = [r for r in requests if r[0] == "/flags"]
                    assert [r[1] for r in flag_requests[:2]] == [status, 200], flag_requests
                    assert len(flag_requests) >= 3, flag_requests
                    assert flag_requests[-1][2]["groups"] == {"company": "acme"}
                    assert flag_requests[-1][2]["group_properties"]["company"] == {"plan": "enterprise"}
                    events = [event for path, _, body in requests if path == "/batch" for event in body["batch"]]
                    called = [event for event in events if event["event"] == "$feature_flag_called"]
                    assert len(called) == 1, called
                    assert called[0]["properties"]["$feature_flag_response"] == "variant-a"
                    assert called[0]["properties"]["$feature_flag"] == "smoke-flag"
                    print(f"PASS native flags {status} retry, cached value, group context, SDK called event "
                          f"({len(flag_requests)} real flags requests retained)")
                call("/reset", {})
            except Exception:
                log.flush()
                log.seek(0)
                print(log.read())
                raise
            finally:
                process.terminate()
                process.wait(timeout=10)
                mock.shutdown()
                mock.server_close()


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--adapter-binary", required=True)
    parser.add_argument("--adapter-port", type=int, required=True)
    parser.add_argument("--mock-port", type=int, required=True)
    args = parser.parse_args()
    run(str(Path(args.adapter_binary).resolve()), args.adapter_port, args.mock_port)
