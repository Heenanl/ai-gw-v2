"""
Test script for OpenAI v1 API via APIM Gateway (through Application Gateway)
"""
import os
import httpx
from openai import OpenAI
from azure.identity import DefaultAzureCredential

# Configuration
# Option 1: Test through Application Gateway (public FQDN with WAF protection)
APIM_ENDPOINT = os.getenv("APIM_ENDPOINT", "https://appgw-yf6mtbaksuydo.westeurope.cloudapp.azure.com")

# Option 2: Test direct to APIM (bypass Application Gateway)
# APIM_ENDPOINT = os.getenv("APIM_ENDPOINT", "https://apim-dev-genaishared-yf6mtbaksuydo.azure-api.net")

MODEL_NAME = "phi-4"  # Using OpenAI v1 API format

# For testing with self-signed certificates only - DO NOT USE IN PRODUCTION
VERIFY_SSL = os.getenv("VERIFY_SSL", "false").lower() == "true"

def test_chat_completion():
    """Test chat completion using OpenAI v1 API format through APIM with managed identity"""
    
    # Get Azure AD token
    credential = DefaultAzureCredential()
    token = credential.get_token("https://cognitiveservices.azure.com/.default")
    
    # Create httpx client with SSL verification disabled for self-signed certs
    http_client = None if VERIFY_SSL else httpx.Client(verify=False)
    
    # Initialize OpenAI client with APIM endpoint and Azure AD token
    client = OpenAI(
        base_url=f"{APIM_ENDPOINT}/v1",
        api_key=token.token,  # Using Azure AD token as API key
        http_client=http_client
    )
    
    try:
        # Make a chat completion request
        response = client.chat.completions.create(
            model=MODEL_NAME,
            messages=[
                {"role": "system", "content": "You are a helpful assistant."},
                {"role": "user", "content": "What is Azure API Management?"}
            ],
            max_tokens=150,
            temperature=0.7
        )
        
        # Print the response
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
    
    credential = DefaultAzureCredential()
    token = credential.get_token("https://cognitiveservices.azure.com/.default")
    
    # Create httpx client with SSL verification disabled for self-signed certs
    http_client = None if VERIFY_SSL else httpx.Client(verify=False)
    
    client = OpenAI(
        base_url=f"{APIM_ENDPOINT}/v1",
        api_key=token.token,
        http_client=http_client
    )
    
    try:
        print("\n✓ Starting streaming completion...")
        
        # Make a streaming chat completion request
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
            # Capture usage from the final chunk
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
    print(f"SSL Verification: {VERIFY_SSL}")
    if not VERIFY_SSL:
        print("⚠️  WARNING: SSL verification is DISABLED (self-signed cert)")
    print("=" * 60)
    
    # Run tests
    test_results = []
    
    print("\n[1/2] Testing chat completion...")
    test_results.append(test_chat_completion())
    
    print("\n[2/2] Testing streaming completion...")
    test_results.append(test_streaming_completion())
    
    # Summary
    print("\n" + "=" * 60)
    print(f"Results: {sum(test_results)}/{len(test_results)} tests passed")
    print("=" * 60)
    
    exit(0 if all(test_results) else 1)
