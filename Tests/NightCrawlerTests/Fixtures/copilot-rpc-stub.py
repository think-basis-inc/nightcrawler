#!/usr/bin/env python3
"""Framed JSON-RPC stub for Copilot metadata-only transport tests."""
import json
import os
import sys
from pathlib import Path

FIXTURE = Path(__file__).with_name("copilot-quota.json")


def quota():
    raw = json.loads(FIXTURE.read_text())
    premium = raw["quotaSnapshots"]["premium_interactions"]
    premium.update(
        entitlementRequests=300,
        usedRequests=90,
        remainingPercentage=70,
        resetDate="2026-10-01T00:00:00Z",
    )
    return raw


def rpc_server(mode):
    for expected in ("ping", "auth.getStatus", "account.getQuota"):
        header = sys.stdin.buffer.readline()
        if not header:
            return
        length = int(header.split(b":")[1])
        assert sys.stdin.buffer.readline() == b"\r\n"
        request = json.loads(sys.stdin.buffer.read(length))
        assert request["method"] == expected and request["params"] == {}
        assert all(
            not os.environ.get(key)
            for key in ("GH_TOKEN", "GITHUB_TOKEN", "COPILOT_GITHUB_TOKEN")
        )
        if mode == "hang":
            sys.stdin.buffer.read()
            return
        if mode == "oversize":
            sys.stdout.buffer.write(b"Content-Length: 999999\r\n\r\n")
            sys.stdout.buffer.flush()
            sys.stdin.buffer.read()
            return
        if expected == "ping":
            result = {"protocolVersion": 3}
        elif expected == "auth.getStatus":
            result = {
                "isAuthenticated": mode != "unauthorized",
                "authType": "user",
                "host": "https://github.com",
                "login": "fixture-user",
            }
        else:
            result = quota()
        reply = {"jsonrpc": "2.0", "id": request["id"], "result": result}
        if mode == "error":
            reply = {
                "jsonrpc": "2.0",
                "id": request["id"],
                "error": {"code": -1, "message": "fixture-secret"},
            }
        body = json.dumps(reply).encode()
        sys.stdout.buffer.write(f"Content-Length: {len(body)}\r\n\r\n".encode() + body)
        sys.stdout.buffer.flush()
        if mode == "unauthorized" and expected == "auth.getStatus":
            leftover = sys.stdin.buffer.read()
            assert not leftover
            return


if __name__ == "__main__":
    if len(sys.argv) == 3 and sys.argv[1] == "--rpc-server":
        rpc_server(sys.argv[2])
    else:
        raise SystemExit(2)
