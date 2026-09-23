#!/usr/bin/env python3
"""Assert the three-model, two-caller access matrix through the local proxy."""

import argparse
import json
import os
import secrets
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen

MODELS = ("demo-chat", "budget-chat", "advanced-chat")
MESSAGES = {
    "missing": "No API key found in request",
    "invalid": "Unauthorized",
    "denied": "You cannot consume this service",
}


def assert_response(status, payload, expected, case):
    try:
        body = json.loads(payload)
    except (ValueError, TypeError):
        return False
    if status != expected:
        return False
    if expected == 200:
        choices = body.get("choices")
        return (isinstance(choices, list) and len(choices) > 0
                and isinstance(choices[0].get("message", {}).get("content"), str)
                and bool(choices[0]["message"]["content"].strip()))
    return body.get("message") == MESSAGES[case] and not body.get("error")


def self_test():
    valid = json.dumps({"choices": [{"message": {"content": "Hello"}}]})
    empty = json.dumps({"choices": [{"message": {"content": ""}}]})
    provider_error = json.dumps({"error": {"message": "upstream unauthorized"}})
    if not assert_response(200, valid, 200, "allowed"):
        raise SystemExit("Verifier rejected a valid completion")
    if assert_response(200, empty, 200, "allowed"):
        raise SystemExit("Verifier accepted an empty completion")
    if assert_response(401, provider_error, 401, "missing"):
        raise SystemExit("Verifier accepted a provider error as gateway auth denial")
    if assert_response(200, valid, 403, "denied"):
        raise SystemExit("Verifier accepted an unauthorized model response")
    for case, status in (("missing", 401), ("invalid", 401), ("denied", 403)):
        if not assert_response(status, json.dumps({"message": MESSAGES[case]}), status, case):
            raise SystemExit(f"Verifier rejected expected {case} response")
    print("Verifier self-test passed")


def request(model, key):
    body = json.dumps({"model": model, "messages": [
        {"role": "user", "content": "Reply with one short greeting."}
    ]}).encode()
    headers = {"Content-Type": "application/json"}
    if key is not None:
        headers["apikey"] = key
    call = Request("http://127.0.0.1:8000/v1/chat/completions",
                   data=body, headers=headers, method="POST")
    try:
        with urlopen(call, timeout=60) as response:
            return response.status, response.read().decode()
    except HTTPError as error:
        return error.code, error.read().decode(errors="replace")
    except URLError as error:
        raise SystemExit(f"Local gateway unavailable: {type(error.reason).__name__}") from error


def live():
    full = os.environ.get("FULL_ACCESS_API_KEY")
    limited = os.environ.get("LIMITED_ACCESS_API_KEY")
    if not full or not limited or full == limited:
        raise SystemExit("Two distinct caller keys are required")
    invalid = secrets.token_urlsafe(32)
    cases = []
    for model in MODELS:
        cases.extend((("full-access", model, full, 200, "allowed"),
                      ("limited-access", model, limited,
                       200 if model == "demo-chat" else 403,
                       "allowed" if model == "demo-chat" else "denied"),
                      ("missing-key", model, None, 401, "missing"),
                      ("invalid-key", model, invalid, 401, "invalid")))
    for caller, model, key, expected, case in cases:
        status, payload = request(model, key)
        passed = assert_response(status, payload, expected, case)
        print(f"{caller:14} {model:14} HTTP {status} " + ("PASS" if passed else "FAIL"))
        if not passed:
            raise SystemExit(f"Unexpected gateway response for {caller} / {model}")
    print("All 12 access checks passed")


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("mode", choices=("self-test", "live"))
    args = parser.parse_args()
    self_test() if args.mode == "self-test" else live()
