import json
import os
import boto3
from botocore.exceptions import ClientError

_ddb = boto3.resource("dynamodb")
_table = _ddb.Table(os.environ["API_KEYS_TABLE"])


def handler(event, context):
    token = _extract_token(event)
    if not token:
        raise Exception("Unauthorized")

    if not _is_valid(token):
        raise Exception("Unauthorized")

    # REST API (v1) uses methodArn; HTTP API (v2) uses routeArn
    arn = event.get("methodArn") or event.get("routeArn", "*")
    return _allow_policy(arn)


def _extract_token(event):
    headers = event.get("headers") or {}
    # REST API preserves original case; HTTP API lowercases headers
    header = headers.get("Authorization") or headers.get("authorization") or ""
    if header.lower().startswith("bearer "):
        return header[7:]
    return None


def _is_valid(token):
    try:
        response = _table.get_item(Key={"api_key": token})
        item = response.get("Item")
        if not item:
            return False
        return item.get("active", False)
    except ClientError:
        return False


def _allow_policy(route_arn="*"):
    # Wildcard over all methods/paths so cached policy works for every endpoint
    # e.g. arn:aws:execute-api:us-east-1:123:abc123/stage/GET/weather → abc123/stage/*/*
    parts = route_arn.split("/")
    wildcard_arn = "/".join(parts[:2]) + "/*/*" if len(parts) >= 2 else "*"
    return {
        "principalId": "api-key",
        "policyDocument": {
            "Version": "2012-10-17",
            "Statement": [{
                "Action": "execute-api:Invoke",
                "Effect": "Allow",
                "Resource": wildcard_arn,
            }],
        },
        "context": {"authorized": "true"},
    }
