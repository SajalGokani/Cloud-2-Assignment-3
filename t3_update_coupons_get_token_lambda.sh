#!/bin/bash
set -e

REGION="us-east-1"
ACCOUNT_ID="000000000000"
API_NAME="coupons"
RESOURCE_PATH="token"
LAMBDA_NAME="coupons_get_token"
ROLE_ARN="arn:aws:iam::000000000000:role/coupons_lambda_role"

echo "=========================================="
echo "PROVISIONING /token & coupons_get_token"
echo "=========================================="

echo "1. Packaging Lambda code with manylinux-compatible dependencies..."
rm -rf package_token coupons_get_token.zip
mkdir -p package_token

pip install \
  --platform manylinux2014_x86_64 \
  --target package_token/ \
  --implementation cp \
  --python-version 3.11 \
  --only-binary=:all: \
  --upgrade \
  bcrypt pyjwt --quiet

cp coupons_get_token.py package_token/
cd package_token
zip -q -r ../coupons_get_token.zip .
cd ..

echo "2. Deploying Lambda function: $LAMBDA_NAME..."
if awslocal lambda get-function --function-name "$LAMBDA_NAME" >/dev/null 2>&1; then
  echo "Updating existing function code..."
  awslocal lambda update-function-code \
    --function-name "$LAMBDA_NAME" \
    --zip-file fileb://coupons_get_token.zip >/dev/null
else
  echo "Creating new function..."
  awslocal lambda create-function \
    --function-name "$LAMBDA_NAME" \
    --runtime python3.11 \
    --role "$ROLE_ARN" \
    --handler coupons_get_token.handler \
    --zip-file fileb://coupons_get_token.zip >/dev/null
fi

if [ -f api_id.txt ]; then
  API_ID=$(cat api_id.txt)
else
  API_ID=$(awslocal apigateway get-rest-apis --query "items[?name=='$API_NAME'].id" --output text)
fi

PARENT_ID=$(awslocal apigateway get-resources --rest-api-id "$API_ID" --query 'items[?path==`/`].id' --output text)
RESOURCE_ID=$(awslocal apigateway get-resources --rest-api-id "$API_ID" --query "items[?path=='/$RESOURCE_PATH'].id" --output text)

if [ -z "$RESOURCE_ID" ] || [ "$RESOURCE_ID" == "None" ]; then
  RESOURCE_ID=$(awslocal apigateway create-resource \
    --rest-api-id "$API_ID" \
    --parent-id "$PARENT_ID" \
    --path-part "$RESOURCE_PATH" \
    --query 'id' --output text)
fi

awslocal apigateway put-method \
  --rest-api-id "$API_ID" \
  --resource-id "$RESOURCE_ID" \
  --http-method POST \
  --authorization-type "NONE" >/dev/null 2>&1 || true

LAMBDA_ARN="arn:aws:lambda:${REGION}:${ACCOUNT_ID}:function:${LAMBDA_NAME}"
INTEGRATION_URI="arn:aws:apigateway:${REGION}:lambda:path/2015-03-31/functions/${LAMBDA_ARN}/invocations"

awslocal apigateway put-integration \
  --rest-api-id "$API_ID" \
  --resource-id "$RESOURCE_ID" \
  --http-method POST \
  --type AWS_PROXY \
  --integration-http-method POST \
  --uri "$INTEGRATION_URI" >/dev/null

awslocal lambda add-permission \
  --function-name "$LAMBDA_NAME" \
  --statement-id "apigateway-token-$(date +%s)" \
  --action "lambda:InvokeFunction" \
  --principal "apigateway.amazonaws.com" \
  --source-arn "arn:aws:execute-api:${REGION}:${ACCOUNT_ID}:${API_ID}/*/*/*" >/dev/null 2>&1 || true

awslocal apigateway create-deployment --rest-api-id "$API_ID" --stage-name prod >/dev/null

echo "Endpoint ready: http://localhost:4566/restapis/${API_ID}/prod/_user_request_/${RESOURCE_PATH}"
