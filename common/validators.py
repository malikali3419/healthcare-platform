from datetime import date
from typing import Optional
from pydantic import BaseModel, EmailStr, field_validator


class PatientRegistrationRequest(BaseModel):
    first_name: str
    last_name: str
    dob: date
    email: EmailStr
    phone: Optional[str] = None

    @field_validator("first_name", "last_name")
    @classmethod
    def name_must_not_be_empty(cls, v: str) -> str:
        if not v.strip():
            raise ValueError("Name must not be empty")
        return v.strip()


class ProviderNoteRequest(BaseModel):
    doctor_id: str
    notes: str

    @field_validator("notes")
    @classmethod
    def notes_must_not_be_empty(cls, v: str) -> str:
        if not v.strip():
            raise ValueError("Notes must not be empty")
        return v.strip()
