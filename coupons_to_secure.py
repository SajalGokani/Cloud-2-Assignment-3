import json
import jwt

JWT_SECRET = "OHXc4w5NEzA61HkV"
JWT_ALGORITHM = "HS256"

def handler(event, context):
    try:
        # Extract token from Authorization header or request body
        headers = event.get('headers') or {}
        auth_header = headers.get('Authorization') or headers.get('authorization') or ""
        
        token = None
        if auth_header.startswith("Bearer "):
            token = auth_header.split(" ")[1].strip()
        elif auth_header:
            token = auth_header.strip()

        # Fallback to check body if token was passed in body
        if not token and event.get('body'):
            body = event.get('body')
            if isinstance(body, str):
                try:
                    body = json.loads(body)
                except Exception:
                    body = {}
            token = body.get('token')

        if not token:
            return {
                "statusCode": 403,
                "headers": {"Content-Type": "application/json"},
                "body": json.dumps({"message": "Forbidden: Missing authentication token"})
            }

        # Validate the token using secret key
        decoded_payload = jwt.decode(token, JWT_SECRET, algorithms=[JWT_ALGORITHM])

        return {
            "statusCode": 200,
            "headers": {"Content-Type": "application/json"},
            "body": json.dumps({
                "message": "Access granted: Token is valid",
                "user": decoded_payload.get("sub"),
                "status": "secure"
            })
        }

    except jwt.ExpiredSignatureError:
        return {
            "statusCode": 403,
            "headers": {"Content-Type": "application/json"},
            "body": json.dumps({"message": "Forbidden: Token has expired"})
        }
    except (jwt.InvalidTokenError, Exception) as e:
        return {
            "statusCode": 403,
            "headers": {"Content-Type": "application/json"},
            "body": json.dumps({"message": "Forbidden: Invalid token", "error": str(e)})
        }
