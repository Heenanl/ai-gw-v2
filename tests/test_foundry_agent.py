"""
Test script for Foundry Agent Service via APIM Gateway

Tests end-to-end flow: Foundry Agent → APIM Connection → APIM Gateway → Backend AI Models

Based on the working pattern from:
  https://github.com/sjuratov/ai-hub-gateway-solution-accelerator/blob/deployment/dev/Testing/
  4. citadel-agent-access-contract-request-tests.ipynb

Prerequisites:
  - pip install azure-ai-projects>=2.0.0 azure-identity
  - Connection 'citadel-hub-connection' deployed in the Foundry project
  - Project managed identity assigned app roles for target deployments
  - az login (with access to the Foundry project)
  - Run from a machine that can reach the Foundry endpoint (e.g., VM in same VNet)

Usage:
  set FOUNDRY_ACCOUNT=aiservices6u2x
  set FOUNDRY_PROJECT=project2
  set FOUNDRY_CONNECTION_NAME=citadel-hub-connection
  set FOUNDRY_MODEL_NAME=gpt-5-mini
  python test_foundry_agent.py
"""
import os
import time
from azure.ai.projects import AIProjectClient
from azure.ai.projects.models import PromptAgentDefinition
from azure.identity import DefaultAzureCredential

# Configuration
FOUNDRY_ACCOUNT = os.getenv("FOUNDRY_ACCOUNT", "aiservices6u2x")
FOUNDRY_PROJECT = os.getenv("FOUNDRY_PROJECT", "project2")
CONNECTION_NAME = os.getenv("FOUNDRY_CONNECTION_NAME", "citadel-hub-connection")
MODEL_NAME = os.getenv("FOUNDRY_MODEL_NAME", "gpt-5-mini")

# Derived
ENDPOINT = f"https://{FOUNDRY_ACCOUNT}.services.ai.azure.com/api/projects/{FOUNDRY_PROJECT}"
DEPLOYMENT_NAME = f"{CONNECTION_NAME}/{MODEL_NAME}"


def test_agent_conversation():
    """Create a prompt agent and run a multi-turn conversation through the APIM gateway."""

    credential = DefaultAzureCredential()
    project_client = AIProjectClient(
        endpoint=ENDPOINT,
        credential=credential
    )

    agent = None
    try:
        # Create prompt agent (matching the reference notebook pattern)
        print("Creating prompt agent...")
        agent = project_client.agents.create_version(
            agent_name="test-gateway-agent",
            definition=PromptAgentDefinition(
                model=DEPLOYMENT_NAME,
                instructions="You are a helpful assistant. Be concise."
            )
        )
        print(f"✓ Agent created (id: {agent.id}, name: {agent.name}, version: {agent.version})")
        print(f"  Endpoint:   {ENDPOINT}")
        print(f"  Deployment: {DEPLOYMENT_NAME}")

        # Run conversation using get_openai_client() as context manager
        test_messages = [
            "What is Azure API Management? Reply in 2-3 sentences.",
            "What are the key benefits of using it with AI services?",
        ]

        with project_client.get_openai_client() as openai_client:
            conversation_id = None

            for i, user_msg in enumerate(test_messages, 1):
                print(f"\n👤 User ({i}/{len(test_messages)}): {user_msg}")

                if conversation_id is None:
                    # Create new conversation with first message
                    conversation = openai_client.conversations.create(
                        items=[{"type": "message", "role": "user", "content": user_msg}],
                    )
                    conversation_id = conversation.id
                    print(f"  Created conversation (id: {conversation_id})")
                else:
                    # Add message to existing conversation
                    openai_client.conversations.items.create(
                        conversation_id=conversation_id,
                        items=[{"type": "message", "role": "user", "content": user_msg}],
                    )

                # Get response from agent
                response = openai_client.responses.create(
                    conversation=conversation_id,
                    extra_body={"agent_reference": {"name": agent.name, "type": "agent_reference"}},
                    input="",
                )

                content = response.output_text if hasattr(response, 'output_text') else str(response)
                print(f"🤖 Agent: {content[:400]}{'...' if len(content) > 400 else ''}")
                time.sleep(1)  # Rate limiting

        print("\n✓ Agent conversation completed successfully!")
        return True

    except Exception as e:
        print(f"\n✗ Error: {e}")
        return False

    finally:
        if agent and project_client:
            try:
                project_client.agents.delete_version(
                    agent_name=agent.name,
                    agent_version=agent.version
                )
                print(f"✓ Agent version cleaned up (name: {agent.name}, version: {agent.version})")
            except Exception as e:
                print(f"⚠ Could not clean up agent: {e}")


if __name__ == "__main__":
    print("=" * 60)
    print("Testing Foundry Agent via APIM Gateway")
    print("=" * 60)
    print(f"Account:    {FOUNDRY_ACCOUNT}")
    print(f"Project:    {FOUNDRY_PROJECT}")
    print(f"Connection: {CONNECTION_NAME}")
    print(f"Model:      {MODEL_NAME}")
    print(f"Endpoint:   {ENDPOINT}")
    print(f"Deployment: {DEPLOYMENT_NAME}")
    print("=" * 60)

    result = test_agent_conversation()

    print("\n" + "=" * 60)
    print(f"Result: {'PASSED' if result else 'FAILED'}")
    print("=" * 60)
    exit(0 if result else 1)
