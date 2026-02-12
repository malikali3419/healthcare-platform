"""
Lambda: GET /patients/{patient_id}/appointments/upcoming
Returns upcoming appointments for a patient.
"""

import sys
import os

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "../.."))

from common.db import execute_query
from common.logger import log_info, log_error, Timer
from common.responses import success, error


def handler(event, context):
    path_params = event.get("pathParameters") or {}
    patient_id = path_params.get("patient_id")

    if not patient_id:
        return error("VALIDATION_ERROR", "patient_id is required")

    with Timer() as t:
        try:
            rows = execute_query(
                """
                SELECT id, provider_name, appointment_time, status
                FROM appointments
                WHERE patient_id = %s
                  AND appointment_time > NOW()
                  AND status = 'scheduled'
                ORDER BY appointment_time ASC
                """,
                (patient_id,),
            )
        except Exception:
            log_error(
                "appointments_fetch_failed",
                patient_id=patient_id,
                error_code="DB_ERROR",
            )
            return error("DB_ERROR", "Failed to fetch appointments", status_code=500)

    log_info(
        "appointments_fetched",
        patient_id=patient_id,
        count=len(rows),
        execution_time_ms=t.duration_ms,
    )

    return success({"appointments": rows})
