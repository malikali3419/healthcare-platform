"""
Lambda: POST /patients/register
Registers a new patient in the database.
"""

import json
import sys
import os

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "../.."))

from pydantic import ValidationError
from common.db import execute_insert
from common.logger import log_info, log_error, Timer
from common.validators import PatientRegistrationRequest
from common.responses import success, error


def handler(event, context):
    try:
        body = json.loads(event.get("body", "{}"))
    except json.JSONDecodeError:
        return error("VALIDATION_ERROR", "Invalid JSON body")

    # Validate input
    try:
        patient = PatientRegistrationRequest(**body)
    except ValidationError as e:
        log_error("patient_registration_failed", error_code="VALIDATION_ERROR")
        return error("VALIDATION_ERROR", str(e))

    # Insert patient
    with Timer() as t:
        try:
            row = execute_insert(
                """
                INSERT INTO patients (first_name, last_name, dob, email, phone)
                VALUES (%s, %s, %s, %s, %s)
                RETURNING id, created_at
                """,
                (
                    patient.first_name,
                    patient.last_name,
                    patient.dob.isoformat(),
                    patient.email,
                    patient.phone,
                ),
            )
        except Exception as e:
            error_msg = str(e)
            if "duplicate key" in error_msg.lower():
                log_error("patient_registration_failed", error_code="DUPLICATE_EMAIL")
                return error(
                    "DUPLICATE_EMAIL",
                    "A patient with this email already exists",
                    status_code=409,
                )
            log_error("patient_registration_failed", error_code="DB_ERROR")
            return error("DB_ERROR", "Failed to register patient", status_code=500)

    log_info(
        "patient_registered",
        patient_id=str(row["id"]),
        execution_time_ms=t.duration_ms,
    )

    return success(
        {"patient_id": str(row["id"]), "created_at": str(row["created_at"])},
        status_code=201,
    )
