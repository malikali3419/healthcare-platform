# Healthcare Platform Backend

A secure, cloud-native healthcare backend built with AWS serverless architecture. Handles patient data, appointments, provider notes, prescriptions, and health education video recommendations.

## Architecture

```
Client
  │
  ▼
API Gateway (HTTP APIs)
  │
  ▼
Lambda Functions (Python)
  │
  ├──▶ PostgreSQL (RDS / local Docker)
  ├──▶ AWS Secrets Manager
  ├──▶ CloudWatch Logs
  └──▶ YouTube Data API v3
```

## Tech Stack

| Layer       | Technology                              |
|-------------|------------------------------------------|
| API Layer   | AWS API Gateway (HTTP APIs)              |
| Compute     | AWS Lambda (Python 3.11)                 |
| Database    | PostgreSQL 15                            |
| Secrets     | AWS Secrets Manager                      |
| Logging     | AWS CloudWatch (structured JSON)         |
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
│   └── schema.sql       # Database DDL
├── infra/localstack/
│   ├── docker-compose.yml
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

Secrets are auto-provisioned via `init.sh`.

### 2. Install Python dependencies

```bash
pip install -r requirements.txt
```

### 3. Set environment

```bash
export ENV=local
```

### 4. Verify secrets

```bash
aws --endpoint-url=http://localhost:4566 secretsmanager get-secret-value \
  --secret-id healthcare/db --query SecretString --output text
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

- **Local/Lambda**: In-memory cache with 1-hour TTL
- **Production**: Recommended to use ElastiCache (Redis) or DynamoDB with TTL

## Environments

| Environment | Purpose | Config |
|-------------|---------|--------|
| `local` | Development (LocalStack) | `ENV=local` |
| `staging` | Pre-production testing | `ENV=staging` |
| `prod` | Live environment | `ENV=prod` |
