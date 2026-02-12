"""
Lambda: POST /appointments/{appointment_id}/notes
Uploads provider notes for an appointment.
"""

import json
import sys
import os

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "../.."))

from pydantic import ValidationError
from common.db import execute_insert, execute_query
from common.logger import log_info, log_error, Timer
from common.validators import ProviderNoteRequest
from common.responses import success, error


def handler(event, context):
    path_params = event.get("pathParameters") or {}
    appointment_id = path_params.get("appointment_id")

    if not appointment_id:
        return error("VALIDATION_ERROR", "appointment_id is required")

    try:
        body = json.loads(event.get("body", "{}"))
    except json.JSONDecodeError:
        return error("VALIDATION_ERROR", "Invalid JSON body")

    # Validate input
    try:
        note_req = ProviderNoteRequest(**body)
    except ValidationError as e:
        log_error("notes_upload_failed", error_code="VALIDATION_ERROR")
        return error("VALIDATION_ERROR", str(e))

    # Verify appointment exists
    try:
        appt = execute_query(
            "SELECT id FROM appointments WHERE id = %s",
            (appointment_id,),
        )
        if not appt:
            return error("NOT_FOUND", "Appointment not found", status_code=404)
    except Exception:
        log_error("notes_upload_failed", error_code="DB_ERROR")
        return error("DB_ERROR", "Failed to verify appointment", status_code=500)

    # Insert notes
    with Timer() as t:
        try:
            row = execute_insert(
                """
                INSERT INTO provider_notes (appointment_id, doctor_id, notes)
                VALUES (%s, %s, %s)
                RETURNING id, created_at
                """,
                (appointment_id, note_req.doctor_id, note_req.notes),
            )
        except Exception:
            log_error("notes_upload_failed", error_code="DB_ERROR")
            return error("DB_ERROR", "Failed to upload notes", status_code=500)

    log_info(
        "notes_uploaded",
        note_id=str(row["id"]),
        appointment_id=appointment_id,
        execution_time_ms=t.duration_ms,
    )

    return success(
        {"note_id": str(row["id"]), "created_at": str(row["created_at"])},
        status_code=201,
    )
