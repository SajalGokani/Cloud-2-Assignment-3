import json
import os
import boto3
import bcrypt
import jwt
from datetime import datetime, timedelta, timezone

JWT_SECRET = "OHXc4w5NEzA61HkV"
JWT_ALGORITHM = "HS256"

# Resolve LocalStack endpoint inside and outside Lambda container
if 'LOCALSTACK_HOSTNAME' in os.environ:
    endpoint_url = f"http://{os.environ['LOCALSTACK_HOSTNAME']}:4566"
elif 'AWS_ENDPOINT_URL' in os.environ:
    endpoint_url = os.environ['AWS_ENDPOINT_URL']
else:
    endpoint_url = "http://localhost:4566"

dynamodb = boto3.resource(
    'dynamodb',
    endpoint_url=endpoint_url,
    region_name='us-east-1'
)
users_table = dynamodb.Table('users')

def handler(event, context):
    try:
        body = event.get('body', {})
        if isinstance(body, str):
            body = json.loads(body)

        username = body.get('username')
        password = body.get('password')

        if not username or not password:
            return {
                "statusCode": 403,
                "headers": {"Content-Type": "application/json"},
                "body": json.dumps({"message": "Forbidden: Missing username or password"})
            }

        response = users_table.get_item(Key={'username': username})
        item = response.get('Item')

        if not item or 'password' not in item:
            return {
                "statusCode": 403,
                "headers": {"Content-Type": "application/json"},
                "body": json.dumps({"message": "Forbidden: Invalid credentials"})
            }

        stored_hashed_password = item['password'].encode('utf-8')
        provided_password = password.encode('utf-8')

        if not bcrypt.checkpw(provided_password, stored_hashed_password):
            return {
                "statusCode": 403,
                "headers": {"Content-Type": "application/json"},
                "body": json.dumps({"message": "Forbidden: Invalid credentials"})
            }

        exp_time = datetime.now(timezone.utc) + timedelta(hours=1)
        payload = {
            "sub": username,
            "exp": exp_time,
            "iat": datetime.now(timezone.utc)
        }

        token = jwt.encode(payload, JWT_SECRET, algorithm=JWT_ALGORITHM)

        return {
            "statusCode": 200,
            "headers": {"Content-Type": "application/json"},
            "body": json.dumps({
                "token": token,
                "expiration": exp_time.strftime("%Y-%m-%dT%H:%M:%SZ")
            })
        }

    except Exception as e:
        return {
            "statusCode": 403,
            "headers": {"Content-Type": "application/json"},
            "body": json.dumps({"message": "Forbidden: Authentication error", "error": str(e)})
        }
