"""
Lambda: GET /patients/{patient_id}/education-videos
Returns health education video recommendations from YouTube Data API.
"""

import sys
import os

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "../.."))

import requests
from common.db import execute_query
from common.secrets import get_secret
from common.logger import log_info, log_error, Timer
from common import cache
from common.responses import success, error

YOUTUBE_SEARCH_URL = "https://www.googleapis.com/youtube/v3/search"
YOUTUBE_SECRET_NAME = "healthcare/youtube"
CACHE_TTL = 3600  # 1 hour


def _fetch_videos(api_key: str, query: str, max_results: int = 5):
    """Call YouTube Data API v3 to search for educational videos."""
    resp = requests.get(
        YOUTUBE_SEARCH_URL,
        params={
            "part": "snippet",
            "q": query,
            "type": "video",
            "maxResults": max_results,
            "key": api_key,
            "safeSearch": "strict",
        },
        timeout=10,
    )
    resp.raise_for_status()
    items = resp.json().get("items", [])
    return [
        {
            "video_id": item["id"]["videoId"],
            "title": item["snippet"]["title"],
            "description": item["snippet"]["description"],
            "url": f"https://www.youtube.com/watch?v={item['id']['videoId']}",
        }
        for item in items
    ]


def handler(event, context):
    path_params = event.get("pathParameters") or {}
    patient_id = path_params.get("patient_id")

    if not patient_id:
        return error("VALIDATION_ERROR", "patient_id is required")

    # Look up patient conditions / medications as search keywords
    try:
        prescriptions = execute_query(
            """
            SELECT DISTINCT medication
            FROM prescriptions
            WHERE patient_id = %s AND status = 'active'
            LIMIT 5
            """,
            (patient_id,),
        )
    except Exception:
        log_error(
            "education_videos_failed",
            patient_id=patient_id,
            error_code="DB_ERROR",
        )
        return error("DB_ERROR", "Failed to look up patient data", status_code=500)

    if not prescriptions:
        search_query = "general health wellness tips"
    else:
        meds = " ".join(row["medication"] for row in prescriptions)
        search_query = f"health education {meds}"

    # Check cache
    cache_key = f"edu_videos:{patient_id}:{search_query}"
    cached = cache.get(cache_key)
    if cached:
        log_info("education_videos_cache_hit", patient_id=patient_id)
        return success({"videos": cached, "source": "cache"})

    # Fetch from YouTube
    with Timer() as t:
        try:
            secret = get_secret(YOUTUBE_SECRET_NAME)
            videos = _fetch_videos(secret["api_key"], search_query)
        except requests.RequestException as e:
            log_error(
                "education_videos_failed",
                patient_id=patient_id,
                error_code="EXTERNAL_API_ERROR",
            )
            return error(
                "EXTERNAL_API_ERROR",
                "Failed to fetch education videos",
                status_code=502,
            )
        except Exception:
            log_error(
                "education_videos_failed",
                patient_id=patient_id,
                error_code="SECRETS_ERROR",
            )
            return error(
                "SECRETS_ERROR",
                "Failed to retrieve API credentials",
                status_code=500,
            )

    cache.set(cache_key, videos, ttl=CACHE_TTL)

    log_info(
        "education_videos_fetched",
        patient_id=patient_id,
        count=len(videos),
        execution_time_ms=t.duration_ms,
    )

    return success({"videos": videos, "source": "youtube"})
