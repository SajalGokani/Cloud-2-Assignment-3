#!/bin/bash
set -e

REGION="us-east-1"
ACCOUNT_ID="000000000000"
API_NAME="coupons"
LAMBDA_NAME="coupons_to_secure"
ROLE_ARN="arn:aws:iam::000000000000:role/coupons_lambda_role"

echo "=========================================="
echo "PROVISIONING /coupons/to_secure & coupons_to_secure"
echo "=========================================="

# 1. Package Lambda with dependencies
echo "1. Packaging Lambda code and dependencies..."
rm -rf package_secure coupons_to_secure.zip
mkdir -p package_secure

pip install \
  --platform manylinux2014_x86_64 \
  --target package_secure/ \
  --implementation cp \
  --python-version 3.11 \
  --only-binary=:all: \
  --upgrade \
  pyjwt --quiet

cp coupons_to_secure.py package_secure/
cd package_secure
zip -q -r ../coupons_to_secure.zip .
cd ..

# 2. Deploy or update Lambda function
echo "2. Deploying Lambda function: $LAMBDA_NAME..."
if awslocal lambda get-function --function-name "$LAMBDA_NAME" >/dev/null 2>&1; then
  echo "Updating existing function code..."
  awslocal lambda update-function-code \
    --function-name "$LAMBDA_NAME" \
    --zip-file fileb://coupons_to_secure.zip >/dev/null
else
  echo "Creating new function..."
  awslocal lambda create-function \
    --function-name "$LAMBDA_NAME" \
    --runtime python3.11 \
    --role "$ROLE_ARN" \
    --handler coupons_to_secure.handler \
    --zip-file fileb://coupons_to_secure.zip >/dev/null
fi

# 3. Retrieve API Gateway ID
if [ -f api_id.txt ]; then
  API_ID=$(cat api_id.txt)
else
  API_ID=$(awslocal apigateway get-rest-apis --query "items[?name=='$API_NAME'].id" --output text)
fi

echo "Using API ID: $API_ID"
PARENT_ROOT_ID=$(awslocal apigateway get-resources --rest-api-id "$API_ID" --query 'items[?path==`/`].id' --output text)

# 4. Check or create parent resource /coupons
COUPONS_RES_ID=$(awslocal apigateway get-resources --rest-api-id "$API_ID" --query "items[?path=='/coupons'].id" --output text)
if [ -z "$COUPONS_RES_ID" ] || [ "$COUPONS_RES_ID" == "None" ]; then
  echo "Creating resource /coupons..."
  COUPONS_RES_ID=$(awslocal apigateway create-resource \
    --rest-api-id "$API_ID" \
    --parent-id "$PARENT_ROOT_ID" \
    --path-part "coupons" \
    --query 'id' --output text)
fi

# 5. Check or create child resource /coupons/to_secure
SECURE_RES_ID=$(awslocal apigateway get-resources --rest-api-id "$API_ID" --query "items[?path=='/coupons/to_secure'].id" --output text)
if [ -z "$SECURE_RES_ID" ] || [ "$SECURE_RES_ID" == "None" ]; then
  echo "Creating resource /coupons/to_secure..."
  SECURE_RES_ID=$(awslocal apigateway create-resource \
    --rest-api-id "$API_ID" \
    --parent-id "$COUPONS_RES_ID" \
    --path-part "to_secure" \
    --query 'id' --output text)
fi
echo "Resource ID for /coupons/to_secure: $SECURE_RES_ID"

# 6. Create GET method on /coupons/to_secure
echo "Creating GET method..."
awslocal apigateway put-method \
  --rest-api-id "$API_ID" \
  --resource-id "$SECURE_RES_ID" \
  --http-method GET \
  --authorization-type "NONE" >/dev/null 2>&1 || true

# 7. Integrate GET method with coupons_to_secure Lambda
echo "Integrating GET method with Lambda..."
LAMBDA_ARN="arn:aws:lambda:${REGION}:${ACCOUNT_ID}:function:${LAMBDA_NAME}"
INTEGRATION_URI="arn:aws:apigateway:${REGION}:lambda:path/2015-03-31/functions/${LAMBDA_ARN}/invocations"

awslocal apigateway put-integration \
  --rest-api-id "$API_ID" \
  --resource-id "$SECURE_RES_ID" \
  --http-method GET \
  --type AWS_PROXY \
  --integration-http-method POST \
  --uri "$INTEGRATION_URI" >/dev/null

# 8. Grant API Gateway permission to invoke Lambda
awslocal lambda add-permission \
  --function-name "$LAMBDA_NAME" \
  --statement-id "apigateway-secure-$(date +%s)" \
  --action "lambda:InvokeFunction" \
  --principal "apigateway.amazonaws.com" \
  --source-arn "arn:aws:execute-api:${REGION}:${ACCOUNT_ID}:${API_ID}/*/*/*" >/dev/null 2>&1 || true

# 9. Deploy API Gateway to 'prod' stage
echo "Deploying to prod stage..."
awslocal apigateway create-deployment --rest-api-id "$API_ID" --stage-name prod >/dev/null

echo "Secure endpoint ready: http://localhost:4566/restapis/${API_ID}/prod/_user_request_/coupons/to_secure"
