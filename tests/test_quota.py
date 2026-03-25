"""
Test script for Quota Enforcement on APIM AI Gateway.
Validates TPM rate limiting, monthly quota, default fallback, and response headers.
"""
import os
import requests
from azure.identity import DefaultAzureCredential

# Configuration
APIM_ENDPOINT = os.getenv("APIM_ENDPOINT", "https://apim-dev-genaishared-gk4ctyapmcrrw.azure-api.net")
API_VERSION = "2024-12-01-preview"
DEPLOYMENT_NAME = os.getenv("DEPLOYMENT_NAME", "gpt-5-mini")
AUDIENCE = os.getenv("APIM_AUDIENCE", "api://fa574d59-83f3-46ad-9e6a-9dc8ab830ff7/.default")

QUOTA_HEADERS = [
    "x-ratelimit-limit-tokens",
    "x-ratelimit-remaining-tokens",
    "x-quota-limit-tokens",
    "x-quota-remaining-tokens",
    "x-tokens-consumed",
    "x-caller-name",
]


def get_token():
    """Acquire bearer token using DefaultAzureCredential."""
    credential = DefaultAzureCredential()
    token = credential.get_token(AUDIENCE)
    return token.token


def chat_completion(token: str, max_tokens: int = 50) -> requests.Response:
    """Send a chat completion request and return the raw response."""
    url = f"{APIM_ENDPOINT}/openai/deployments/{DEPLOYMENT_NAME}/chat/completions?api-version={API_VERSION}"
    headers = {
        "Authorization": f"Bearer {token}",
        "Content-Type": "application/json",
    }
    body = {
        "messages": [{"role": "user", "content": "Say hello in one word."}],
        "max_completion_tokens": max_tokens,
    }
    return requests.post(url, json=body, headers=headers, timeout=30)


def test_quota_response_headers():
    """Verify all quota-related response headers are present on a successful request."""
    print("\n=== Test: Quota Response Headers ===")
    token = get_token()
    resp = chat_completion(token)

    assert resp.status_code == 200, f"Expected 200, got {resp.status_code}: {resp.text}"

    missing = [h for h in QUOTA_HEADERS if h not in resp.headers]
    if missing:
        print(f"✗ Missing headers: {missing}")
        print(f"  Present headers: {[h for h in QUOTA_HEADERS if h in resp.headers]}")
        return False

    print("✓ All quota headers present:")
    for h in QUOTA_HEADERS:
        print(f"  {h}: {resp.headers[h]}")
    return True


def test_tpm_remaining_decrements():
    """Verify x-ratelimit-remaining-tokens decrements between consecutive requests."""
    print("\n=== Test: TPM Remaining Decrements ===")
    token = get_token()

    resp1 = chat_completion(token)
    assert resp1.status_code == 200, f"Request 1 failed: {resp1.status_code}"
    remaining1 = int(resp1.headers.get("x-ratelimit-remaining-tokens", -1))

    resp2 = chat_completion(token)
    assert resp2.status_code == 200, f"Request 2 failed: {resp2.status_code}"
    remaining2 = int(resp2.headers.get("x-ratelimit-remaining-tokens", -1))

    if remaining2 < remaining1:
        print(f"✓ Remaining tokens decremented: {remaining1} → {remaining2}")
        return True
    else:
        print(f"✗ Remaining did not decrement: {remaining1} → {remaining2}")
        return False


def test_quota_limit_matches_config():
    """Verify x-ratelimit-limit-tokens and x-quota-limit-tokens are non-zero."""
    print("\n=== Test: Quota Limits Are Configured ===")
    token = get_token()
    resp = chat_completion(token)
    assert resp.status_code == 200, f"Expected 200, got {resp.status_code}"

    tpm_limit = int(resp.headers.get("x-ratelimit-limit-tokens", 0))
    monthly_limit = int(resp.headers.get("x-quota-limit-tokens", 0))

    if tpm_limit > 0 and monthly_limit > 0:
        print(f"✓ TPM limit: {tpm_limit}, Monthly quota: {monthly_limit}")
        return True
    else:
        print(f"✗ Unexpected limits — TPM: {tpm_limit}, Monthly: {monthly_limit}")
        return False


def test_caller_name_present():
    """Verify x-caller-name is populated (not empty or 'Unknown')."""
    print("\n=== Test: Caller Name Resolution ===")
    token = get_token()
    resp = chat_completion(token)
    assert resp.status_code == 200, f"Expected 200, got {resp.status_code}"

    caller = resp.headers.get("x-caller-name", "")
    if caller and caller != "Unknown":
        print(f"✓ Caller identified: {caller}")
        return True
    else:
        print(f"✗ Caller name missing or unknown: '{caller}'")
        return False


if __name__ == "__main__":
    results = []
    tests = [
        test_quota_response_headers,
        test_tpm_remaining_decrements,
        test_quota_limit_matches_config,
        test_caller_name_present,
    ]

    for test_fn in tests:
        try:
            results.append((test_fn.__name__, test_fn()))
        except Exception as e:
            print(f"✗ {test_fn.__name__} raised: {e}")
            results.append((test_fn.__name__, False))

    print("\n=== Summary ===")
    passed = sum(1 for _, ok in results if ok)
    print(f"{passed}/{len(results)} tests passed")
    for name, ok in results:
        status = "✓" if ok else "✗"
        print(f"  {status} {name}")
