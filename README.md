# Healthcare Platform Backend

A secure, cloud-native healthcare backend built with AWS serverless architecture. Handles patient data, appointments, provider notes, prescriptions, and health education video recommendations.

## Architecture

```
Client
  |
  v
API Gateway (REST API)
  |
  v
Lambda Functions (Python 3.12)
  |
  |-->  PostgreSQL (Docker)
  |-->  AWS Secrets Manager
  |-->  CloudWatch Logs
  '-->  YouTube Data API v3
```

## Tech Stack

| Layer       | Technology                              |
|-------------|------------------------------------------|
| API Layer   | AWS API Gateway (REST API)               |
| Compute     | AWS Lambda (Python 3.12)                 |
| Database    | PostgreSQL 15                            |
| Secrets     | AWS Secrets Manager                      |
| Logging     | AWS CloudWatch (structured JSON)         |
| Docs        | Swagger UI (OpenAPI 3.0)                 |
| Local Dev   | LocalStack + Docker Compose              |

## Project Structure

```
healthcare-platform/
├── lambdas/
│   ├── register_patient/handler.py
│   ├── get_upcoming_appointments/handler.py
│   ├── upload_provider_notes/handler.py
│   ├── list_prescriptions/handler.py
│   └── education_videos/handler.py
├── common/
│   ├── db.py            # Database connection & query helpers
│   ├── secrets.py       # AWS Secrets Manager integration
│   ├── logger.py        # Structured JSON logging (PHI-safe)
│   ├── validators.py    # Pydantic input validation models
│   ├── cache.py         # In-memory TTL cache
│   └── responses.py     # Standardized API response helpers
├── schema/
│   ├── schema.sql       # Database DDL
│   └── swagger.json     # OpenAPI 3.0 specification
├── infra/localstack/
│   ├── docker-compose.yml
│   ├── deploy.sh        # Lambda + API Gateway deployment script
│   ├── test_apis.sh     # End-to-end API test script
│   └── init.sh          # Auto-provisions secrets on startup
├── requirements.txt
└── README.md
```

## API Endpoints

| Method | Endpoint | Description |
|--------|----------|-------------|
| POST   | `/patients/register` | Register a new patient |
| GET    | `/patients/{patient_id}/appointments/upcoming` | Get upcoming appointments |
| POST   | `/appointments/{appointment_id}/notes` | Upload provider notes |
| GET    | `/patients/{patient_id}/prescriptions?status=active` | List prescriptions |
| GET    | `/patients/{patient_id}/education-videos` | Get education video recommendations |

## Quick Start (Local Development)

### Prerequisites

- Docker & Docker Compose
- Python 3.11+
- AWS CLI

### 1. Start services

```bash
cd infra/localstack
docker compose up -d
```

This starts:
- **LocalStack** on port 4566 (API Gateway, Lambda, Secrets Manager, CloudWatch)
- **PostgreSQL** on port 5432 (auto-runs schema.sql)
- **Swagger UI** on port 8080 (interactive API documentation)

Secrets are auto-provisioned via `init.sh`.

### 2. Install Python dependencies

```bash
pip install -r requirements.txt
```

### 3. Deploy Lambdas & API Gateway

```bash
cd infra/localstack
bash deploy.sh
```

This packages all Lambda functions (with Linux-targeted dependencies), creates them in LocalStack, sets up API Gateway with all routes and CORS support, and deploys to a `local` stage.

### 4. Run end-to-end tests

```bash
cd infra/localstack
bash test_apis.sh
```

This registers a test patient, seeds test data, and hits all 5 API endpoints.

### 5. Verify secrets

```bash
aws --endpoint-url=http://localhost:4566 secretsmanager get-secret-value \
  --secret-id healthcare/db --query SecretString --output text
```

## Swagger UI

Interactive API documentation is available via Swagger UI at:

```
http://localhost:8080
```

Swagger UI is automatically started as part of `docker compose up -d`. It reads the OpenAPI 3.0 spec from `schema/swagger.json`.

To use Swagger UI with your deployed API:
1. Open http://localhost:8080 in your browser
2. Update the `apiId` server variable with the API ID from `deploy.sh` output
3. Use the "Try it out" button on any endpoint to send requests

## Database Schema

### Tables

| Table | Description |
|-------|-------------|
| `patients` | Registered patients (id, first_name, last_name, dob, email, phone) |
| `appointments` | Patient appointments (id, patient_id, provider_name, appointment_time, status) |
| `provider_notes` | Doctor notes per appointment (id, appointment_id, doctor_id, notes) |
| `prescriptions` | Patient prescriptions (id, patient_id, medication, dosage, status) |

### Seeding Test Data (Appointments & Prescriptions)

Since the assignment spec does not include create endpoints for appointments and prescriptions, these records are inserted directly into the database via SQL.

Connect to the database:

```bash
docker exec -it healthcare-postgres psql -U postgres -d healthcare
```

#### Insert an appointment

```sql
INSERT INTO appointments (patient_id, provider_name, appointment_time, status)
VALUES ('<PATIENT_ID>', 'Dr. Adams', NOW() + INTERVAL '7 days', 'scheduled');
```

#### Insert a prescription

```sql
INSERT INTO prescriptions (patient_id, medication, dosage, status)
VALUES ('<PATIENT_ID>', 'Metformin', '500mg twice daily', 'active');
```

## CloudWatch Logs

View Lambda logs via LocalStack:

```bash
# List log groups
aws --endpoint-url=http://localhost:4566 logs describe-log-groups

# View logs for a specific Lambda
aws --endpoint-url=http://localhost:4566 logs describe-log-streams \
  --log-group-name /aws/lambda/register_patient

# Tail real-time logs from LocalStack container
docker logs -f healthcare-localstack
```

## Security & Compliance

### PHI Protection

The following fields are **never logged**:
- Patient names, emails, phone numbers
- Date of birth
- Provider notes content
- Prescription details

### What is logged (structured JSON)

```json
{
  "level": "INFO",
  "event": "appointments_fetched",
  "patient_id": "uuid",
  "count": 3,
  "execution_time_ms": 34
}
```

## Error Handling

All errors follow a standard format:

```json
{
  "error": {
    "code": "NOT_FOUND",
    "message": "Patient not found"
  }
}
```

| Error Code | HTTP Status | Description |
|------------|-------------|-------------|
| VALIDATION_ERROR | 400 | Invalid input |
| NOT_FOUND | 404 | Resource not found |
| DUPLICATE_EMAIL | 409 | Email already registered |
| DB_ERROR | 500 | Database failure |
| EXTERNAL_API_ERROR | 502 | YouTube API failure |
| SECRETS_ERROR | 500 | Secrets Manager failure |

## Caching

- **Education Videos**: In-memory cache with 1-hour TTL to reduce YouTube API calls
- The response includes a `"source"` field (`"youtube"` or `"cache"`) indicating the data origin
- **Production**: Recommended to use ElastiCache (Redis) or DynamoDB with TTL

## Environments

| Environment | Purpose | Config |
|-------------|---------|--------|
| `local` | Development (LocalStack) | `ENV=local` |
