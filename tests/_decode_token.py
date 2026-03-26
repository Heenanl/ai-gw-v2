"""Decode the JWT token for the APIM audience to inspect claims."""
from azure.identity import DefaultAzureCredential
import base64
import json

cred = DefaultAzureCredential()
token = cred.get_token("api://fa574d59-83f3-46ad-9e6a-9dc8ab830ff7/.default").token

# Decode JWT payload (no signature verification)
payload = token.split(".")[1]
payload += "=" * (4 - len(payload) % 4)
claims = json.loads(base64.b64decode(payload))

print("=== JWT Claims ===")
for key in ["aud", "iss", "roles", "oid", "sub", "appid", "upn", "name", "ver", "idtyp", "wids"]:
    print(f"{key:8s}: {claims.get(key)}")

# Write full claims to file for inspection
with open("jwt_claims.json", "w") as f:
    json.dump(claims, f, indent=2)
print("\nFull claims written to jwt_claims.json")
