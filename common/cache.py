import time

_cache = {}

DEFAULT_TTL_SECONDS = 3600  # 1 hour


def get(key: str):
    """Return cached value if it exists and has not expired, else None."""
    entry = _cache.get(key)
    if entry and entry["expires_at"] > time.time():
        return entry["data"]
    # Expired or missing — remove stale entry
    _cache.pop(key, None)
    return None


def set(key: str, data, ttl: int = DEFAULT_TTL_SECONDS):
    """Store a value in the cache with a TTL."""
    _cache[key] = {
        "data": data,
        "expires_at": time.time() + ttl,
    }
