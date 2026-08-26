"""
Test script for OpenAI v1 API via APIM Gateway
"""
import os
from pathlib import Path
from dotenv import load_dotenv
from openai import OpenAI
from azure.identity import DefaultAzureCredential, get_bearer_token_provider

load_dotenv(Path(__file__).parent / ".env")

# Configuration
APIM_ENDPOINT = os.getenv("APIM_ENDPOINT", "https://apim-dev-genaishared-gk4ctyapmcrrw.azure-api.net")
MODEL_NAME = os.getenv("MODEL_NAME", "gpt-5-mini")
APIM_AUDIENCE = os.getenv("APIM_AUDIENCE", "api://fa574d59-83f3-46ad-9e6a-9dc8ab830ff7")

def get_client():
    """Create OpenAI client with Entra ID token for APIM gateway"""
    credential = DefaultAzureCredential()
    token_provider = get_bearer_token_provider(credential, f"{APIM_AUDIENCE}/.default")
    token = token_provider()

    return OpenAI(
        base_url=f"{APIM_ENDPOINT}/v1",
        api_key=token  # pass token string as api_key
    )

def test_model_discovery():
    """Test role-filtered OpenAI v1 model discovery through APIM."""
    client = get_client()

    try:
        models = client.models.list()
        model_ids = [model.id for model in models.data]

        print(f"✓ Model discovery successful ({len(model_ids)} models)")
        for model_id in model_ids:
            print(f"  - {model_id}")

        if MODEL_NAME not in model_ids:
            print(f"✗ Configured model '{MODEL_NAME}' is not available to this identity")
            return False

        return True

    except Exception as e:
        print(f"✗ Error during model discovery: {e}")
        return False

def test_model_retrieval():
    """Test retrieval of an authorized model through APIM."""
    client = get_client()

    try:
        model = client.models.retrieve(MODEL_NAME)
        print(f"✓ Model retrieval successful: {model.id}")
        return model.id == MODEL_NAME

    except Exception as e:
        print(f"✗ Error during model retrieval: {e}")
        return False

def test_chat_completion():
    """Test chat completion using OpenAI v1 API format through APIM"""
    client = get_client()

    try:
        response = client.chat.completions.create(
            model=MODEL_NAME,
            messages=[
                {"role": "system", "content": "You are a helpful assistant."},
                {"role": "user", "content": "What is Azure API Management?"}
            ],
            max_tokens=150,
            temperature=0.7
        )

        print("✓ Chat completion successful!")
        print(f"\nModel: {response.model}")
        print(f"\nResponse:\n{response.choices[0].message.content}")
        print(f"\nUsage:")
        print(f"  Prompt tokens: {response.usage.prompt_tokens}")
        print(f"  Completion tokens: {response.usage.completion_tokens}")
        print(f"  Total tokens: {response.usage.total_tokens}")

        return True

    except Exception as e:
        print(f"✗ Error during chat completion: {e}")
        return False

def test_streaming_completion():
    """Test streaming chat completion using OpenAI v1 API format through APIM"""
    client = get_client()

    try:
        print("\n✓ Starting streaming completion...")

        stream = client.chat.completions.create(
            model=MODEL_NAME,
            messages=[
                {"role": "user", "content": "What is Azure API Management?"}
            ],
            max_tokens=100,
            stream=True
        )

        print("\nStreamed response:")
        usage_info = None
        for chunk in stream:
            if chunk.choices and len(chunk.choices) > 0 and chunk.choices[0].delta.content:
                print(chunk.choices[0].delta.content, end="", flush=True)
            if hasattr(chunk, 'usage') and chunk.usage:
                usage_info = chunk.usage

        print("\n")
        if usage_info:
            print(f"\nUsage:")
            print(f"  Prompt tokens: {usage_info.prompt_tokens}")
            print(f"  Completion tokens: {usage_info.completion_tokens}")
            print(f"  Total tokens: {usage_info.total_tokens}")

        print("\n✓ Streaming completion successful!")
        return True

    except Exception as e:
        print(f"\n✗ Error during streaming completion: {e}")
        return False

if __name__ == "__main__":
    print("=" * 60)
    print("Testing OpenAI v1 API via APIM Gateway")
    print("=" * 60)
    print(f"Endpoint: {APIM_ENDPOINT}/v1")
    print(f"Model: {MODEL_NAME}")
    print("=" * 60)

    test_results = []

    print("\n[1/4] Testing model discovery...")
    test_results.append(test_model_discovery())

    print("\n[2/4] Testing model retrieval...")
    test_results.append(test_model_retrieval())

    print("\n[3/4] Testing chat completion...")
    test_results.append(test_chat_completion())

    print("\n[4/4] Testing streaming completion...")
    test_results.append(test_streaming_completion())

    print("\n" + "=" * 60)
    print(f"Results: {sum(test_results)}/{len(test_results)} tests passed")
    print("=" * 60)

    exit(0 if all(test_results) else 1)