"""
Lambda: GET /patients/{patient_id}/prescriptions?status=active
Lists prescriptions for a patient, optionally filtered by status.
"""

import sys
import os

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "../.."))

from common.db import execute_query
from common.logger import log_info, log_error, Timer
from common.responses import success, error

VALID_STATUSES = {"active", "past"}


def handler(event, context):
    path_params = event.get("pathParameters") or {}
    patient_id = path_params.get("patient_id")

    if not patient_id:
        return error("VALIDATION_ERROR", "patient_id is required")

    query_params = event.get("queryStringParameters") or {}
    status_filter = query_params.get("status")

    if status_filter and status_filter not in VALID_STATUSES:
        return error(
            "VALIDATION_ERROR",
            f"Invalid status filter. Must be one of: {', '.join(VALID_STATUSES)}",
        )

    with Timer() as t:
        try:
            if status_filter:
                rows = execute_query(
                    """
                    SELECT id, medication, dosage, status, created_at
                    FROM prescriptions
                    WHERE patient_id = %s AND status = %s
                    ORDER BY created_at DESC
                    """,
                    (patient_id, status_filter),
                )
            else:
                rows = execute_query(
                    """
                    SELECT id, medication, dosage, status, created_at
                    FROM prescriptions
                    WHERE patient_id = %s
                    ORDER BY created_at DESC
                    """,
                    (patient_id,),
                )
        except Exception:
            log_error(
                "prescriptions_fetch_failed",
                patient_id=patient_id,
                error_code="DB_ERROR",
            )
            return error("DB_ERROR", "Failed to fetch prescriptions", status_code=500)

    log_info(
        "prescriptions_fetched",
        patient_id=patient_id,
        count=len(rows),
        status_filter=status_filter,
        execution_time_ms=t.duration_ms,
    )

    return success({"prescriptions": rows})
