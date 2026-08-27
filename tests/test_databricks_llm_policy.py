import unittest
import xml.etree.ElementTree as ET
from pathlib import Path


REPO_ROOT = Path(__file__).parents[1]
POLICY_PATH = REPO_ROOT / "apim-policies" / "databricks-policy.xml"
MODULE_PATH = REPO_ROOT / "infra" / "modules" / "databricks-llm-api.bicep"
ENTRYPOINT_PATH = REPO_ROOT / "infra" / "databricks.bicep"


class DatabricksLlmPolicyTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.policy = POLICY_PATH.read_text(encoding="utf-8")
        cls.module = MODULE_PATH.read_text(encoding="utf-8")
        cls.entrypoint = ENTRYPOINT_PATH.read_text(encoding="utf-8")
        cls.policy_root = ET.fromstring(cls.policy)

    def test_policy_uses_generic_llm_telemetry(self):
        self.assertIsNotNone(self.policy_root.find(".//llm-emit-token-metric"))
        self.assertNotIn("azure-openai-emit-token-metric", self.policy)
        self.assertIn('namespace="DatabricksLLM"', self.policy)

    def test_policy_requests_usage_for_streaming_responses(self):
        self.assertIn("stream_options", self.policy)
        self.assertIn("include_usage", self.policy)
        self.assertIn('buffer-response="false"', self.policy)

    def test_backend_credential_is_stored_as_a_secret_named_value(self):
        self.assertIn("@secure()", self.module)
        self.assertIn("secret: true", self.module)
        self.assertIn("{{databricks-api-token}}", self.policy)
        self.assertNotIn("databricksApiToken =", self.entrypoint)

    def test_api_requires_a_configurable_app_role(self):
        self.assertIn("{{databricks-required-role}}", self.policy)
        self.assertIn("param requiredRole string", self.module)
        self.assertIn("requiredRole: requiredRole", self.entrypoint)

    def test_api_is_imported_with_the_openai_schema(self):
        self.assertIn("format: 'openapi+json'", self.module)
        self.assertIn("loadTextContent('../openapi/openai-v1.json')", self.entrypoint)
        self.assertIn("databricks-openai-api", self.module)

    def test_api_enables_application_insights_metrics(self):
        self.assertIn("service/apis/diagnostics@2024-06-01-preview", self.module)
        self.assertIn("name: 'applicationinsights'", self.module)
        self.assertIn("largeLanguageModel:", self.module)
        self.assertIn("logs: 'enabled'", self.module)
        self.assertIn("metrics: true", self.module)


if __name__ == "__main__":
    unittest.main()
