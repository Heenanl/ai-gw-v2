"""
Test script for Azure OpenAI Embeddings API via APIM Gateway
"""
import os
from pathlib import Path
from dotenv import load_dotenv
from openai import AzureOpenAI
from azure.identity import DefaultAzureCredential, get_bearer_token_provider

load_dotenv(Path(__file__).parent / ".env")

# Configuration
APIM_ENDPOINT = os.getenv("APIM_ENDPOINT", "https://apim-dev-genaishared-gk4ctyapmcrrw.azure-api.net")
API_VERSION = os.getenv("API_VERSION", "2024-12-01-preview")
DEPLOYMENT_NAME = os.getenv("EMBEDDINGS_DEPLOYMENT_NAME", "text-embedding-3-small")
APIM_AUDIENCE = os.getenv("APIM_AUDIENCE", "api://fa574d59-83f3-46ad-9e6a-9dc8ab830ff7")


def test_single_embedding():
    """Test single text embedding via APIM"""

    credential = DefaultAzureCredential()
    token_provider = get_bearer_token_provider(
        credential,
        f"{APIM_AUDIENCE}/.default"
    )

    client = AzureOpenAI(
        azure_endpoint=APIM_ENDPOINT,
        api_version=API_VERSION,
        azure_ad_token_provider=token_provider
    )

    try:
        response = client.embeddings.create(
            model=DEPLOYMENT_NAME,
            input="Azure API Management is a hybrid, multicloud management platform for APIs."
        )

        print("✓ Single embedding successful!")
        print(f"\nModel: {response.model}")
        print(f"Embedding dimensions: {len(response.data[0].embedding)}")
        print(f"First 5 values: {response.data[0].embedding[:5]}")
        print(f"\nUsage:")
        print(f"  Prompt tokens: {response.usage.prompt_tokens}")
        print(f"  Total tokens: {response.usage.total_tokens}")

        return True

    except Exception as e:
        print(f"✗ Error during single embedding: {e}")
        return False


def test_batch_embeddings():
    """Test batch embeddings (multiple inputs) via APIM"""

    credential = DefaultAzureCredential()
    token_provider = get_bearer_token_provider(
        credential,
        f"{APIM_AUDIENCE}/.default"
    )

    client = AzureOpenAI(
        azure_endpoint=APIM_ENDPOINT,
        api_version=API_VERSION,
        azure_ad_token_provider=token_provider
    )

    try:
        texts = [
            "Azure API Management is a hybrid, multicloud management platform for APIs.",
            "Azure OpenAI provides access to OpenAI's models including GPT-4.",
            "Embeddings are useful for semantic search and RAG patterns.",
        ]

        response = client.embeddings.create(
            model=DEPLOYMENT_NAME,
            input=texts
        )

        print("✓ Batch embeddings successful!")
        print(f"\nModel: {response.model}")
        print(f"Number of embeddings: {len(response.data)}")
        for i, item in enumerate(response.data):
            print(f"  [{i}] dimensions: {len(item.embedding)}, first 3: {item.embedding[:3]}")
        print(f"\nUsage:")
        print(f"  Prompt tokens: {response.usage.prompt_tokens}")
        print(f"  Total tokens: {response.usage.total_tokens}")

        return True

    except Exception as e:
        print(f"✗ Error during batch embeddings: {e}")
        return False


if __name__ == "__main__":
    print("=" * 60)
    print("Testing Azure OpenAI Embeddings API via APIM Gateway")
    print("=" * 60)
    print(f"Endpoint: {APIM_ENDPOINT}")
    print(f"Deployment: {DEPLOYMENT_NAME}")
    print("=" * 60)

    test_results = []

    print("\n[1/2] Testing single embedding...")
    test_results.append(test_single_embedding())

    print("\n[2/2] Testing batch embeddings...")
    test_results.append(test_batch_embeddings())

    # Summary
    print("\n" + "=" * 60)
    print(f"Results: {sum(test_results)}/{len(test_results)} tests passed")
    print("=" * 60)

    exit(0 if all(test_results) else 1)
