import os
import json
import boto3

_secrets_cache = {}


def _get_client():
    env = os.environ.get("ENV", "local")
    if env == "local":
        # Inside a LocalStack Lambda container, LOCALSTACK_HOSTNAME points
        # to the LocalStack gateway. Fall back to localhost for direct use.
        ls_host = os.environ.get("LOCALSTACK_HOSTNAME", "localhost")
        endpoint = f"http://{ls_host}:4566"
        return boto3.client(
            "secretsmanager",
            endpoint_url=endpoint,
            region_name="us-east-1",
            aws_access_key_id="test",
            aws_secret_access_key="test",
        )
    return boto3.client("secretsmanager")


def get_secret(secret_name: str) -> dict:
    """Retrieve and cache a secret from AWS Secrets Manager."""
    if secret_name in _secrets_cache:
        return _secrets_cache[secret_name]

    client = _get_client()
    response = client.get_secret_value(SecretId=secret_name)
    secret = json.loads(response["SecretString"])
    _secrets_cache[secret_name] = secret
    return secret
