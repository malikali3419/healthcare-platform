#!/bin/bash
# Deploy all Lambda functions and create API Gateway routes in LocalStack
set -e

ENDPOINT="http://localhost:4566"
REGION="us-east-1"
PROJECT_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
DEPLOY_DIR="/tmp/healthcare-lambda-deploy"
ACCOUNT_ID="000000000000"

export AWS_PAGER=""
export AWS_ACCESS_KEY_ID="test"
export AWS_SECRET_ACCESS_KEY="test"
export AWS_DEFAULT_REGION="$REGION"
aws="aws --endpoint-url=$ENDPOINT --region=$REGION"

echo "=== Healthcare Platform — LocalStack Deployment ==="
echo "Project root: $PROJECT_ROOT"

# -------------------------------------------------------
# 1. Package Lambda code
# -------------------------------------------------------
echo ""
echo "[1/4] Packaging Lambda functions..."

rm -rf "$DEPLOY_DIR"
mkdir -p "$DEPLOY_DIR"

# Install dependencies targeting Linux (Lambda runtime runs in a Linux container)
pip install -r "$PROJECT_ROOT/requirements.txt" -t "$DEPLOY_DIR/layer" \
    --platform manylinux2014_x86_64 --only-binary=:all: --quiet

LAMBDAS=("register_patient" "get_upcoming_appointments" "upload_provider_notes" "list_prescriptions" "education_videos")

for fn in "${LAMBDAS[@]}"; do
    echo "  Packaging $fn..."
    WORK="$DEPLOY_DIR/$fn"
    mkdir -p "$WORK"

    # Copy handler
    cp "$PROJECT_ROOT/lambdas/$fn/handler.py" "$WORK/"

    # Copy common utilities
    cp -r "$PROJECT_ROOT/common" "$WORK/common"

    # Copy installed dependencies
    cp -r "$DEPLOY_DIR/layer/"* "$WORK/" 2>/dev/null || true

    # Create zip
    (cd "$WORK" && zip -r "$DEPLOY_DIR/$fn.zip" . -q)
done

echo "  Done."

# -------------------------------------------------------
# 2. Create Lambda functions
# -------------------------------------------------------
echo ""
echo "[2/4] Creating Lambda functions..."

for fn in "${LAMBDAS[@]}"; do
    echo "  Creating $fn..."

    # Delete if exists (idempotent redeploy)
    $aws lambda delete-function --function-name "$fn" 2>/dev/null || true

    $aws lambda create-function \
        --function-name "$fn" \
        --runtime python3.12 \
        --handler handler.handler \
        --role "arn:aws:iam::${ACCOUNT_ID}:role/lambda-role" \
        --zip-file "fileb://$DEPLOY_DIR/$fn.zip" \
        --timeout 30 \
        --environment "Variables={ENV=local}" > /dev/null
done

echo "  Done."

# -------------------------------------------------------
# 3. Create REST API Gateway
# -------------------------------------------------------
echo ""
echo "[3/4] Creating API Gateway..."

# Delete any existing healthcare-api (idempotent redeploy)
OLD_IDS=$($aws apigateway get-rest-apis --query 'items[?name==`healthcare-api`].id' --output text)
for old_id in $OLD_IDS; do
    echo "  Deleting old API: $old_id"
    $aws apigateway delete-rest-api --rest-api-id "$old_id" 2>/dev/null || true
done

# Create the API
API_ID=$($aws apigateway create-rest-api \
    --name "healthcare-api" \
    --query 'id' --output text)

echo "  API ID: $API_ID"

# Get root resource ID
ROOT_ID=$($aws apigateway get-resources \
    --rest-api-id "$API_ID" \
    --query 'items[0].id' --output text)

# --- Helper function to create a resource path ---
create_resource() {
    local parent_id=$1
    local path_part=$2
    $aws apigateway create-resource \
        --rest-api-id "$API_ID" \
        --parent-id "$parent_id" \
        --path-part "$path_part" \
        --query 'id' --output text
}

# --- Helper to wire method → Lambda ---
create_method_and_integration() {
    local resource_id=$1
    local http_method=$2
    local function_name=$3

    $aws apigateway put-method \
        --rest-api-id "$API_ID" \
        --resource-id "$resource_id" \
        --http-method "$http_method" \
        --authorization-type "NONE" > /dev/null

    LAMBDA_URI="arn:aws:apigateway:$REGION:lambda:path/2015-03-31/functions/arn:aws:lambda:$REGION:$ACCOUNT_ID:function:$function_name/invocations"

    $aws apigateway put-integration \
        --rest-api-id "$API_ID" \
        --resource-id "$resource_id" \
        --http-method "$http_method" \
        --type AWS_PROXY \
        --integration-http-method POST \
        --uri "$LAMBDA_URI" > /dev/null
}

# --- Helper to add OPTIONS (CORS preflight) to a resource ---
enable_cors() {
    local resource_id=$1

    $aws apigateway put-method \
        --rest-api-id "$API_ID" \
        --resource-id "$resource_id" \
        --http-method OPTIONS \
        --authorization-type "NONE" > /dev/null

    $aws apigateway put-integration \
        --rest-api-id "$API_ID" \
        --resource-id "$resource_id" \
        --http-method OPTIONS \
        --type MOCK \
        --request-templates '{"application/json": "{\"statusCode\": 200}"}' > /dev/null

    $aws apigateway put-method-response \
        --rest-api-id "$API_ID" \
        --resource-id "$resource_id" \
        --http-method OPTIONS \
        --status-code 200 \
        --response-parameters '{"method.response.header.Access-Control-Allow-Origin": false, "method.response.header.Access-Control-Allow-Methods": false, "method.response.header.Access-Control-Allow-Headers": false}' > /dev/null

    $aws apigateway put-integration-response \
        --rest-api-id "$API_ID" \
        --resource-id "$resource_id" \
        --http-method OPTIONS \
        --status-code 200 \
        --response-parameters '{"method.response.header.Access-Control-Allow-Origin": "'"'"'*'"'"'", "method.response.header.Access-Control-Allow-Methods": "'"'"'GET,POST,OPTIONS'"'"'", "method.response.header.Access-Control-Allow-Headers": "'"'"'Content-Type,Accept'"'"'"}' > /dev/null
}

# Build resource tree and wire integrations:
#
#   POST /patients/register                          → register_patient
#   GET  /patients/{patient_id}/appointments/upcoming → get_upcoming_appointments
#   POST /appointments/{appointment_id}/notes         → upload_provider_notes
#   GET  /patients/{patient_id}/prescriptions         → list_prescriptions
#   GET  /patients/{patient_id}/education-videos      → education_videos

echo "  Creating routes..."

# /patients
PATIENTS_ID=$(create_resource "$ROOT_ID" "patients")

# /patients/register  → POST
REGISTER_ID=$(create_resource "$PATIENTS_ID" "register")
create_method_and_integration "$REGISTER_ID" "POST" "register_patient"
enable_cors "$REGISTER_ID"
echo "    POST /patients/register"

# /patients/{patient_id}
PATIENT_ID_RES=$(create_resource "$PATIENTS_ID" "{patient_id}")

# /patients/{patient_id}/appointments
APPTS_ID=$(create_resource "$PATIENT_ID_RES" "appointments")

# /patients/{patient_id}/appointments/upcoming  → GET
UPCOMING_ID=$(create_resource "$APPTS_ID" "upcoming")
create_method_and_integration "$UPCOMING_ID" "GET" "get_upcoming_appointments"
enable_cors "$UPCOMING_ID"
echo "    GET  /patients/{patient_id}/appointments/upcoming"

# /patients/{patient_id}/prescriptions  → GET
PRESCRIPTIONS_ID=$(create_resource "$PATIENT_ID_RES" "prescriptions")
create_method_and_integration "$PRESCRIPTIONS_ID" "GET" "list_prescriptions"
enable_cors "$PRESCRIPTIONS_ID"
echo "    GET  /patients/{patient_id}/prescriptions"

# /patients/{patient_id}/education-videos  → GET
VIDEOS_ID=$(create_resource "$PATIENT_ID_RES" "education-videos")
create_method_and_integration "$VIDEOS_ID" "GET" "education_videos"
enable_cors "$VIDEOS_ID"
echo "    GET  /patients/{patient_id}/education-videos"

# /appointments
APPOINTMENTS_ID=$(create_resource "$ROOT_ID" "appointments")

# /appointments/{appointment_id}
APPT_ID_RES=$(create_resource "$APPOINTMENTS_ID" "{appointment_id}")

# /appointments/{appointment_id}/notes  → POST
NOTES_ID=$(create_resource "$APPT_ID_RES" "notes")
create_method_and_integration "$NOTES_ID" "POST" "upload_provider_notes"
enable_cors "$NOTES_ID"
echo "    POST /appointments/{appointment_id}/notes"

# -------------------------------------------------------
# 4. Deploy the API
# -------------------------------------------------------
echo ""
echo "[4/4] Deploying API to 'local' stage..."

$aws apigateway create-deployment \
    --rest-api-id "$API_ID" \
    --stage-name "local" > /dev/null

BASE_URL="$ENDPOINT/restapis/$API_ID/local/_user_request_"

echo ""
echo "=== Deployment Complete ==="
echo ""
echo "Base URL: $BASE_URL"
echo ""
echo "Endpoints:"
echo "  POST $BASE_URL/patients/register"
echo "  GET  $BASE_URL/patients/{patient_id}/appointments/upcoming"
echo "  POST $BASE_URL/appointments/{appointment_id}/notes"
echo "  GET  $BASE_URL/patients/{patient_id}/prescriptions?status=active"
echo "  GET  $BASE_URL/patients/{patient_id}/education-videos"
echo ""
