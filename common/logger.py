import json
import logging
import time

logger = logging.getLogger("healthcare")
logger.setLevel(logging.INFO)

if not logger.handlers:
    handler = logging.StreamHandler()
    handler.setFormatter(logging.Formatter("%(message)s"))
    logger.addHandler(handler)


def log_info(event: str, **kwargs):
    """Emit a structured JSON log entry. Never include PHI fields."""
    entry = {"level": "INFO", "event": event, **kwargs}
    logger.info(json.dumps(entry, default=str))


def log_error(event: str, error_code: str = None, **kwargs):
    """Emit a structured JSON error log entry."""
    entry = {"level": "ERROR", "event": event, "error_code": error_code, **kwargs}
    logger.error(json.dumps(entry, default=str))


class Timer:
    """Context manager for measuring execution time in milliseconds."""

    def __enter__(self):
        self.start = time.time()
        return self

    def __exit__(self, *args):
        self.duration_ms = round((time.time() - self.start) * 1000, 2)
