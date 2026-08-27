import base64
import json
import unittest
import xml.etree.ElementTree as ET
from pathlib import Path


REPO_ROOT = Path(__file__).parents[1]
POLICY_PATH = REPO_ROOT / "apim-policies" / "oaiv1-models-policy.xml"
OPENAPI_PATH = REPO_ROOT / "openapi" / "openai-v1.json"
BICEP_POLICY_MODULE_PATH = REPO_ROOT / "infra" / "modules" / "apim-policies.bicep"


class OpenAIModelsPolicyTests(unittest.TestCase):
    def test_policy_renders_model_catalog_without_xml_escaping_issues(self):
        model_names = [
            "gpt-5-mini",
            "model-with-\"quotes\"",
            "modèle-unicode",
        ]
        encoded_models = base64.b64encode(
            json.dumps(model_names, separators=(",", ":")).encode("utf-8")
        ).decode("ascii")

        rendered_policy = POLICY_PATH.read_text(encoding="utf-8").replace(
            "__MODEL_NAMES_BASE64__", encoded_models
        )

        ET.fromstring(rendered_policy)
        self.assertNotIn("__MODEL_NAMES_BASE64__", rendered_policy)
        self.assertEqual(
            model_names,
            json.loads(base64.b64decode(encoded_models).decode("utf-8")),
        )

        bicep_module = BICEP_POLICY_MODULE_PATH.read_text(encoding="utf-8")
        self.assertIn(
            "base64(string(modelNames))",
            bicep_module,
        )

    def test_openapi_declares_model_discovery_operations(self):
        specification = json.loads(OPENAPI_PATH.read_text(encoding="utf-8"))

        self.assertEqual(
            "listModels", specification["paths"]["/models"]["get"]["operationId"]
        )
        self.assertEqual(
            "retrieveModel",
            specification["paths"]["/models/{model}"]["get"]["operationId"],
        )


if __name__ == "__main__":
    unittest.main()