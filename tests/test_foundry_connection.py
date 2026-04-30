"""
Test Foundry -> APIM Gateway connection directly (no agent deployment needed).

Uses the OpenAI Responses API through AIProjectClient to route requests via
the APIM connection. The model is specified as connection_name/model_name,
which tells Foundry to route through the APIM gateway connection.

Prerequisites:
  - pip install azure-ai-projects>=2.0.0 azure-identity openai
  - APIM connection deployed in the Foundry project (via foundry-integration/main.bicep)
  - Project managed identity assigned app roles for target deployments
  - az login

Usage:
  set FOUNDRY_ACCOUNT=aiservicesktdp
  set FOUNDRY_PROJECT=projectktdp
  set FOUNDRY_CONNECTION_NAME=citadel-hub-connection
  set MODEL_NAME=gpt-5-mini
  python test_foundry_connection.py
"""
import os
from pathlib import Path
from dotenv import load_dotenv
from azure.ai.projects import AIProjectClient
from azure.identity import DefaultAzureCredential

load_dotenv(Path(__file__).parent / ".env")

# Configuration
FOUNDRY_ACCOUNT = os.getenv("FOUNDRY_ACCOUNT", "aiservicesktdp")
FOUNDRY_PROJECT = os.getenv("FOUNDRY_PROJECT", "projectktdp")
CONNECTION_NAME = os.getenv("FOUNDRY_CONNECTION_NAME", "citadel-hub-connection")
MODEL_NAME = os.getenv("MODEL_NAME", "gpt-5-mini")

ENDPOINT = f"https://{FOUNDRY_ACCOUNT}.services.ai.azure.com/api/projects/{FOUNDRY_PROJECT}"
# Foundry routes through the connection when model is prefixed with connection_name
DEPLOYMENT_NAME = f"{CONNECTION_NAME}/{MODEL_NAME}"


def create_client():
    """Create an OpenAI client via AIProjectClient, routed through the Foundry project."""
    credential = DefaultAzureCredential()
    project_client = AIProjectClient(endpoint=ENDPOINT, credential=credential)
    return project_client.get_openai_client()


def test_responses_api():
    """Test the Responses API routed through the Foundry APIM connection."""
    client = create_client()

    print(f"Endpoint:   {ENDPOINT}")
    print(f"Base URL:   {client.base_url}")
    print(f"Connection: {CONNECTION_NAME}")
    print(f"Model:      {DEPLOYMENT_NAME}")
    print("-" * 50)

    print(f"\nSending response request for: {DEPLOYMENT_NAME}")
    response = client.responses.create(
        model=DEPLOYMENT_NAME,
        input="Say hello in one sentence.",
    )

    print(f"Response:   {response.output_text}")
    print(f"Model:      {response.model}")
    print(f"Tokens:     prompt={response.usage.input_tokens}, completion={response.usage.output_tokens}")
    print("\n[PASS] Responses API test passed!")
    return True


def test_responses_api_streaming():
    """Streaming test via the Responses API through the Foundry APIM connection."""
    client = create_client()

    print(f"\nStreaming response for: {DEPLOYMENT_NAME}")
    stream = client.responses.create(
        model=DEPLOYMENT_NAME,
        input="Count from 1 to 5.",
        stream=True,
    )

    print("Response:   ", end="")
    for event in stream:
        if event.type == "response.output_text.delta":
            print(event.delta, end="", flush=True)
    print("\n\n[PASS] Streaming test passed!")
    return True


if __name__ == "__main__":
    print("=" * 50)
    print("Foundry -> APIM Gateway Connection Test")
    print("(No agent deployment required)")
    print("=" * 50)

    passed = 0
    failed = 0

    for test_fn in [test_responses_api, test_responses_api_streaming]:
        try:
            test_fn()
            passed += 1
        except Exception as e:
            print(f"\n[FAIL] {test_fn.__name__} failed: {e}")
            failed += 1

    print("\n" + "=" * 50)
    print(f"Results: {passed} passed, {failed} failed")
    print("=" * 50)
    exit(0 if failed == 0 else 1)
