#!/bin/bash
# End-to-end test for all 5 Healthcare Platform APIs via LocalStack API Gateway
set -e

ENDPOINT="http://localhost:4566"
REGION="us-east-1"

export AWS_PAGER=""
export AWS_ACCESS_KEY_ID="test"
export AWS_SECRET_ACCESS_KEY="test"
export AWS_DEFAULT_REGION="$REGION"
aws="aws --endpoint-url=$ENDPOINT --region=$REGION"

# Find the API ID
API_ID=$($aws apigateway get-rest-apis --query 'items[?name==`healthcare-api`].id' --output text | awk '{print $NF}')

if [ -z "$API_ID" ]; then
    echo "ERROR: healthcare-api not found. Run deploy.sh first."
    exit 1
fi

BASE="$ENDPOINT/restapis/$API_ID/local/_user_request_"

echo "=== Healthcare Platform API Tests ==="
echo "Base URL: $BASE"
echo ""

# -------------------------------------------------------
# Test 1: Register Patient
# -------------------------------------------------------
echo "--- Test 1: POST /patients/register ---"
REGISTER_RESP=$(curl -s -X POST "$BASE/patients/register" \
    -H "Content-Type: application/json" \
    -d '{
        "first_name": "Jane",
        "last_name": "Smith",
        "dob": "1985-03-20",
        "email": "jane.smith@example.com",
        "phone": "555-0199"
    }')
echo "$REGISTER_RESP" | python3 -m json.tool 2>/dev/null || echo "$REGISTER_RESP"

PATIENT_ID=$(echo "$REGISTER_RESP" | python3 -c "import sys,json; print(json.loads(sys.stdin.read())['data']['patient_id'])" 2>/dev/null || echo "")

if [ -z "$PATIENT_ID" ]; then
    echo "WARNING: Could not extract patient_id. Subsequent tests may fail."
    PATIENT_ID="00000000-0000-0000-0000-000000000000"
fi
echo ""

# -------------------------------------------------------
# Test 2: Register duplicate (should fail with 409)
# -------------------------------------------------------
echo "--- Test 2: POST /patients/register (duplicate email — expect error) ---"
curl -s -X POST "$BASE/patients/register" \
    -H "Content-Type: application/json" \
    -d '{
        "first_name": "Jane",
        "last_name": "Smith",
        "dob": "1985-03-20",
        "email": "jane.smith@example.com"
    }' | python3 -m json.tool 2>/dev/null
echo ""

# -------------------------------------------------------
# Insert test data directly into Postgres for remaining tests
# -------------------------------------------------------
echo "--- Seeding test data into Postgres ---"
docker exec healthcare-postgres psql -U postgres -d healthcare -c "
    -- Insert appointment for the patient
    INSERT INTO appointments (patient_id, provider_name, appointment_time, status)
    VALUES ('$PATIENT_ID', 'Dr. Adams', NOW() + INTERVAL '7 days', 'scheduled');

    -- Insert a past appointment (for notes test)
    INSERT INTO appointments (patient_id, provider_name, appointment_time, status)
    VALUES ('$PATIENT_ID', 'Dr. Baker', NOW() - INTERVAL '1 day', 'completed');

    -- Insert prescriptions
    INSERT INTO prescriptions (patient_id, medication, dosage, status)
    VALUES ('$PATIENT_ID', 'Metformin', '500mg twice daily', 'active');

    INSERT INTO prescriptions (patient_id, medication, dosage, status)
    VALUES ('$PATIENT_ID', 'Ibuprofen', '200mg as needed', 'past');
" 2>/dev/null
echo "  Done."
echo ""

# -------------------------------------------------------
# Test 3: Get Upcoming Appointments
# -------------------------------------------------------
echo "--- Test 3: GET /patients/$PATIENT_ID/appointments/upcoming ---"
curl -s "$BASE/patients/$PATIENT_ID/appointments/upcoming" | python3 -m json.tool 2>/dev/null
echo ""

# -------------------------------------------------------
# Test 4: Upload Provider Notes
# -------------------------------------------------------
echo "--- Test 4: POST /appointments/{id}/notes ---"

# Get the completed appointment ID
APPT_ID=$(docker exec healthcare-postgres psql -U postgres -d healthcare -t -c \
    "SELECT id FROM appointments WHERE patient_id='$PATIENT_ID' AND status='completed' LIMIT 1;" 2>/dev/null | tr -d ' \n')

if [ -n "$APPT_ID" ]; then
    curl -s -X POST "$BASE/appointments/$APPT_ID/notes" \
        -H "Content-Type: application/json" \
        -d "{
            \"doctor_id\": \"d1234567-abcd-abcd-abcd-123456789abc\",
            \"notes\": \"Patient reports improved blood sugar levels. Continue current medication.\"
        }" | python3 -m json.tool 2>/dev/null
else
    echo "WARNING: No appointment found to attach notes to."
fi
echo ""

# -------------------------------------------------------
# Test 5: List Prescriptions (active only)
# -------------------------------------------------------
echo "--- Test 5: GET /patients/$PATIENT_ID/prescriptions?status=active ---"
curl -s "$BASE/patients/$PATIENT_ID/prescriptions?status=active" | python3 -m json.tool 2>/dev/null
echo ""

# -------------------------------------------------------
# Test 6: List All Prescriptions (no filter)
# -------------------------------------------------------
echo "--- Test 6: GET /patients/$PATIENT_ID/prescriptions (all) ---"
curl -s "$BASE/patients/$PATIENT_ID/prescriptions" | python3 -m json.tool 2>/dev/null
echo ""

# -------------------------------------------------------
# Test 7: Education Videos
# -------------------------------------------------------
echo "--- Test 7: GET /patients/$PATIENT_ID/education-videos ---"
echo "(Note: will return EXTERNAL_API_ERROR unless a real YouTube API key is configured)"
curl -s "$BASE/patients/$PATIENT_ID/education-videos" | python3 -m json.tool 2>/dev/null
echo ""

echo "=== All tests complete ==="
