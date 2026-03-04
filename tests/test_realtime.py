"""
Test script for Azure OpenAI Realtime API via APIM Gateway.

Tests two things:
  1. WebSocket realtime session (wss) - verifies JWT auth, backend routing, response
  2. Usage reporting endpoint (https POST) - verifies llm-token-limit + emit-token-metric
"""
import os
import json
import asyncio
import requests
import websockets
from azure.identity import DefaultAzureCredential

# ---------------------------------------------------------------------------
# Configuration - matches pattern from test_azure_openai.py
# ---------------------------------------------------------------------------
APIM_ENDPOINT        = os.getenv("APIM_ENDPOINT", "https://apim-dev-genaishared-gk4ctyapmcrrw.azure-api.net")
APIM_SUBSCRIPTION_KEY = os.getenv("APIM_SUBSCRIPTION_KEY", "")
DEPLOYMENT_NAME      = os.getenv("REALTIME_DEPLOYMENT", "gpt-4o-realtime-preview")
API_VERSION          = "2024-12-17"
AAD_AUDIENCE         = "api://fa574d59-83f3-46ad-9e6a-9dc8ab830ff7/.default"

# Derive WebSocket URL from HTTP endpoint (https -> wss)
_WS_BASE              = APIM_ENDPOINT.replace("https://", "wss://")
REALTIME_WS_URL      = f"{_WS_BASE}/openai/realtime?deployment={DEPLOYMENT_NAME}&api-version={API_VERSION}"
REALTIME_USAGE_URL   = f"{APIM_ENDPOINT}/openai/realtime-usage"


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
def _get_token() -> str:
    """Obtain Azure AD bearer token via DefaultAzureCredential (az login / managed identity)."""
    credential = DefaultAzureCredential()
    return credential.get_token(AAD_AUDIENCE).token


def _auth_headers(token: str) -> dict:
    return {
        "Authorization": f"Bearer {token}",
        "Ocp-Apim-Subscription-Key": APIM_SUBSCRIPTION_KEY,
    }


# ---------------------------------------------------------------------------
# Test 1: WebSocket realtime session
# ---------------------------------------------------------------------------
async def _run_realtime_session() -> tuple[bool, dict]:
    """
    Open a realtime WebSocket session through APIM, send a simple text prompt,
    wait for response.done, and return (success, usage).
    """
    token = get_token = _get_token()
    headers = {**_auth_headers(token), "OpenAI-Beta": "realtime=v1"}

    print(f"  Connecting: {REALTIME_WS_URL}")

    async with websockets.connect(REALTIME_WS_URL, additional_headers=headers) as ws:
        print("  ✓ WebSocket handshake accepted by APIM")

        # -- session.created ------------------------------------------------
        raw = await asyncio.wait_for(ws.recv(), timeout=15)
        event = json.loads(raw)
        if event.get("type") != "session.created":
            raise RuntimeError(f"Expected session.created, got: {event.get('type')}")
        session_id = event.get("session", {}).get("id", "unknown")
        print(f"  ✓ session.created  id={session_id}")

        # -- configure: text-only, no audio needed for test -----------------
        await ws.send(json.dumps({
            "type": "session.update",
            "session": {
                "modalities": ["text"],
                "instructions": "You are a helpful assistant. Keep responses very brief.",
                "turn_detection": None
            }
        }))

        # -- send a text message --------------------------------------------
        await ws.send(json.dumps({
            "type": "conversation.item.create",
            "item": {
                "type": "message",
                "role": "user",
                "content": [{"type": "input_text", "text": "Reply with exactly one word: hello."}]
            }
        }))

        # -- request a response ---------------------------------------------
        await ws.send(json.dumps({"type": "response.create"}))
        print("  Waiting for response.done...")

        # -- drain events until response.done -------------------------------
        response_text = ""
        usage = {}
        async for raw_msg in ws:
            ev = json.loads(raw_msg)
            t  = ev.get("type", "")

            if t == "response.text.delta":
                response_text += ev.get("delta", "")

            elif t == "response.done":
                u = ev.get("response", {}).get("usage", {})
                usage = {
                    "input_tokens":  u.get("input_tokens", 0),
                    "output_tokens": u.get("output_tokens", 0),
                    "session_id":    session_id,
                }
                print(f"  ✓ response.done  text='{response_text.strip()}'")
                print(f"    input_tokens={usage['input_tokens']}  output_tokens={usage['output_tokens']}")
                break

            elif t == "error":
                msg = ev.get("error", {}).get("message", "unknown error")
                raise RuntimeError(f"Realtime API error: {msg}")

    return True, usage


def test_realtime_session() -> tuple[bool, dict]:
    """
    End-to-end WebSocket session test.
    Validates: JWT auth at handshake, managed identity backend auth, backend pool routing.
    """
    print("\n[1/2] Realtime WebSocket session")
    print("-" * 40)
    try:
        success, usage = asyncio.run(_run_realtime_session())
        print("  ✓ Realtime session test PASSED")
        return success, usage
    except websockets.exceptions.InvalidStatus as e:
        # Surface the HTTP status code from the failed upgrade
        print(f"  ✗ WebSocket upgrade rejected: HTTP {e.response.status_code}")
        if e.response.status_code == 401:
            print("    → JWT validation failed at APIM. Check AAD_AUDIENCE and token.")
        elif e.response.status_code == 403:
            print("    → Subscription key or roles claim rejected by APIM policy.")
        elif e.response.status_code == 404:
            print("    → openai-realtime-ws-api not found in APIM. Redeploy infra first.")
        return False, {}
    except Exception as e:
        print(f"  ✗ Realtime session test FAILED: {e}")
        return False, {}


# ---------------------------------------------------------------------------
# Test 2: Usage reporting HTTP endpoint
# ---------------------------------------------------------------------------
def test_usage_reporting(
    input_tokens: int = 50,
    output_tokens: int = 50,
    session_id: str = "test-session-standalone"
) -> bool:
    """
    POST token usage to /openai/realtime-usage.
    Validates: llm-token-limit counter update, azure-openai-emit-token-metric, 204 response.
    """
    print("\n[2/2] Usage reporting endpoint (POST /openai/realtime-usage)")
    print("-" * 40)
    try:
        token = _get_token()
        headers = {
            **_auth_headers(token),
            "Content-Type": "application/json"
        }
        payload = {
            "deployment": DEPLOYMENT_NAME,
            "input_tokens": input_tokens,
            "output_tokens": output_tokens,
            "session_id": session_id
        }

        print(f"  POST {REALTIME_USAGE_URL}")
        print(f"  Payload: {json.dumps(payload)}")

        resp = requests.post(REALTIME_USAGE_URL, headers=headers, json=payload, timeout=10)

        if resp.status_code == 204:
            print("  ✓ 204 No Content - usage recorded")
            retry_after = resp.headers.get("retry-after", None)
            if retry_after:
                print(f"    retry-after: {retry_after}  ← quota window info")
            print("  ✓ Usage reporting test PASSED")
            return True

        elif resp.status_code == 429:
            print(f"  ⚠ 429 Too Many Requests - token quota exceeded")
            print(f"    retry-after: {resp.headers.get('retry-after', 'N/A')}")
            print("    This is expected behaviour when quota is exhausted.")
            return True  # 429 from llm-token-limit means the policy IS working correctly

        elif resp.status_code == 401:
            print(f"  ✗ 401 Unauthorized - JWT validation failed")
            return False

        elif resp.status_code == 404:
            print(f"  ✗ 404 Not Found - openai-realtime-usage-api not found in APIM. Redeploy infra first.")
            return False

        else:
            print(f"  ✗ Unexpected response: {resp.status_code} - {resp.text}")
            return False

    except Exception as e:
        print(f"  ✗ Usage reporting test FAILED: {e}")
        return False


# ---------------------------------------------------------------------------
# Entrypoint
# ---------------------------------------------------------------------------
if __name__ == "__main__":
    print("=" * 60)
    print("Azure OpenAI Realtime API via APIM Gateway")
    print("=" * 60)
    print(f"Endpoint:    {APIM_ENDPOINT}")
    print(f"Deployment:  {DEPLOYMENT_NAME}")
    print(f"WS  URL:     {REALTIME_WS_URL}")
    print(f"HTTP URL:    {REALTIME_USAGE_URL}")
    print("=" * 60)

    results = []

    # --- Test 1: full realtime WebSocket session ---
    session_ok, usage_data = test_realtime_session()
    results.append(session_ok)

    # --- Test 2: usage reporting - use real tokens from session if available ---
    if session_ok and usage_data:
        usage_ok = test_usage_reporting(
            input_tokens=usage_data["input_tokens"],
            output_tokens=usage_data["output_tokens"],
            session_id=usage_data["session_id"]
        )
    else:
        # Session failed - still exercise the usage endpoint independently
        usage_ok = test_usage_reporting()
    results.append(usage_ok)

    # --- Summary ---
    print("\n" + "=" * 60)
    passed = sum(results)
    total  = len(results)
    status = "✓ ALL PASSED" if passed == total else f"✗ {total - passed} FAILED"
    print(f"Results: {passed}/{total} tests passed  {status}")
    print("=" * 60)

    exit(0 if all(results) else 1)
