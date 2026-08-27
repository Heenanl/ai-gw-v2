"""Test script for the Databricks OpenAI-compatible API via APIM Gateway."""

import os
from pathlib import Path

from azure.identity import DefaultAzureCredential
from dotenv import load_dotenv
from openai import OpenAI


load_dotenv(Path(__file__).parent / ".env")

# Configuration
APIM_ENDPOINT = os.getenv(
    "APIM_ENDPOINT", "https://apim-dev-genaishared-gk4ctyapmcrrw.azure-api.net"
)
APIM_AUDIENCE = os.getenv(
    "APIM_AUDIENCE", "api://fa574d59-83f3-46ad-9e6a-9dc8ab830ff7"
)
DATABRICKS_MODEL = os.getenv("DATABRICKS_MODEL", "databricks-gpt-oss-20b")


def create_client() -> OpenAI:
    """Create an OpenAI client authenticated to APIM with Microsoft Entra ID."""
    credential = DefaultAzureCredential()
    token = credential.get_token(f"{APIM_AUDIENCE}/.default")
    return OpenAI(
        base_url=f"{APIM_ENDPOINT.rstrip('/')}/databricks/v1",
        api_key=token.token,
    )


def test_chat_completion() -> bool:
    """Test a non-streaming Databricks completion through APIM."""
    try:
        response = create_client().chat.completions.create(
            model=DATABRICKS_MODEL,
            messages=[
                {"role": "system", "content": "You are a helpful assistant."},
                {"role": "user", "content": "What is Azure API Management?"},
            ],
            max_tokens=200,
        )

        if response.usage is None:
            raise RuntimeError("Databricks did not return token usage")

        print("[OK] Chat completion successful!")
        print(f"\nModel: {response.model}")
        print(f"\nResponse:\n{response.choices[0].message.content}")
        print("\nUsage:")
        print(f"  Prompt tokens: {response.usage.prompt_tokens}")
        print(f"  Completion tokens: {response.usage.completion_tokens}")
        print(f"  Total tokens: {response.usage.total_tokens}")
        return True
    except Exception as error:
        print(f"[ERROR] Error during chat completion: {error}")
        return False


def test_streaming_completion() -> bool:
    """Test a streaming Databricks completion and its final usage through APIM."""
    try:
        print("\n[OK] Starting streaming completion...")
        stream = create_client().chat.completions.create(
            model=DATABRICKS_MODEL,
            messages=[{"role": "user", "content": "What is Azure API Management?"}],
            max_tokens=200,
            stream=True,
            stream_options={"include_usage": True},
        )

        print("\nStreamed response:")
        usage_info = None
        for chunk in stream:
            if chunk.choices and chunk.choices[0].delta.content:
                print(chunk.choices[0].delta.content, end="", flush=True)
            if chunk.usage is not None:
                usage_info = chunk.usage

        print("\n")
        if usage_info is None:
            raise RuntimeError("Databricks did not return final streaming usage")

        print("Usage:")
        print(f"  Prompt tokens: {usage_info.prompt_tokens}")
        print(f"  Completion tokens: {usage_info.completion_tokens}")
        print(f"  Total tokens: {usage_info.total_tokens}")
        print("\n[OK] Streaming completion successful!")
        return True
    except Exception as error:
        print(f"\n[ERROR] Error during streaming completion: {error}")
        return False


if __name__ == "__main__":
    print("=" * 60)
    print("Testing Databricks API via APIM Gateway")
    print("=" * 60)
    print(f"Endpoint: {APIM_ENDPOINT.rstrip('/')}/databricks/v1")
    print(f"Model: {DATABRICKS_MODEL}")
    print("=" * 60)

    test_results = []

    print("\n[1/2] Testing chat completion...")
    test_results.append(test_chat_completion())

    print("\n[2/2] Testing streaming completion...")
    test_results.append(test_streaming_completion())

    print("\n" + "=" * 60)
    print(f"Results: {sum(test_results)}/{len(test_results)} tests passed")
    print("=" * 60)

    raise SystemExit(0 if all(test_results) else 1)
