import json
import os
import boto3
from botocore.exceptions import ClientError

_ddb = boto3.resource("dynamodb", region_name=os.environ["AWS_REGION"])
_table = _ddb.Table(os.environ["API_KEYS_TABLE"])


def handler(event, context):
    token = _extract_token(event)
    if not token:
        raise Exception("Unauthorized")

    if not _is_valid(token):
        raise Exception("Unauthorized")

    return _allow_policy(event["routeArn"])


def _extract_token(event):
    header = event.get("headers", {}).get("authorization", "")
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


def _allow_policy(route_arn):
    return {
        "principalId": "api-key",
        "policyDocument": {
            "Version": "2012-10-17",
            "Statement": [{
                "Action": "execute-api:Invoke",
                "Effect": "Allow",
                "Resource": route_arn,
            }],
        },
        "context": {"authorized": "true"},
    }
