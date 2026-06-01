"""Hand-written ERP REST client (no SDK).

Handles: X-API-Key auth, cursor pagination (until has_more=False),
incremental ?updated_after, 429 rate-limiting (Retry-After + backoff),
and transient 5xx/timeout retries (exponential backoff, max 5).
"""
from __future__ import annotations
import logging
import random
import time

import requests

logger = logging.getLogger(__name__)

DEFAULT_TIMEOUT = (10, 30)        # (connect, read) seconds
DEFAULT_PAGE_LIMIT = 100
MAX_TRANSIENT_ATTEMPTS = 5        # 500 / timeout retries (per brief)
MAX_RATELIMIT_ATTEMPTS = 10       # safety cap so a 429 storm can't loop forever
BACKOFF_BASE = 1.0
BACKOFF_CAP = 60.0


class TransientAPIError(Exception):
    """5xx or network error worth retrying."""


class ERPClient:
    def __init__(self, base_url, api_key, *, page_limit=DEFAULT_PAGE_LIMIT, timeout=DEFAULT_TIMEOUT):
        self.base_url = base_url.rstrip("/")
        self.page_limit = page_limit
        self.timeout = timeout
        self.session = requests.Session()
        self.session.headers.update({"X-API-Key": api_key, "Accept": "application/json"})

    def _backoff(self, attempt):
        delay = min(BACKOFF_BASE * (2 ** (attempt - 1)), BACKOFF_CAP)
        return delay + random.uniform(0, delay * 0.1)  # jitter

    def _get(self, path, params):
        url = f"{self.base_url}/{path.lstrip('/')}"
        transient = 0
        ratelimit = 0
        while True:
            try:
                resp = self.session.get(url, params=params, timeout=self.timeout)
            except (requests.Timeout, requests.ConnectionError) as exc:
                transient += 1
                if transient >= MAX_TRANSIENT_ATTEMPTS:
                    raise TransientAPIError(f"network error after {transient} attempts: {exc}") from exc
                wait = self._backoff(transient)
                logger.warning("network error %s (attempt %d), retry in %.1fs: %s", url, transient, wait, exc)
                time.sleep(wait)
                continue

            if resp.status_code == 429:
                ratelimit += 1
                if ratelimit > MAX_RATELIMIT_ATTEMPTS:
                    resp.raise_for_status()
                try:
                    wait = float(resp.headers.get("Retry-After", ""))
                except (TypeError, ValueError):
                    wait = self._backoff(ratelimit)
                logger.warning("429 rate-limited %s, waiting %.1fs", url, wait)
                time.sleep(wait)
                continue

            if resp.status_code >= 500:
                transient += 1
                if transient >= MAX_TRANSIENT_ATTEMPTS:
                    resp.raise_for_status()
                wait = self._backoff(transient)
                logger.warning("%d on %s (attempt %d), retry in %.1fs", resp.status_code, url, transient, wait)
                time.sleep(wait)
                continue

            resp.raise_for_status()   # other 4xx (401/403/404) -> fail fast, no retry
            return resp.json()

    def fetch_entity(self, path, updated_after=None):
        """Yield every record for an entity, following cursor pagination."""
        cursor = None
        page = 0
        while True:
            params = {"limit": self.page_limit}
            if cursor:
                params["cursor"] = cursor
            if updated_after:
                params["updated_after"] = updated_after
            body = self._get(path, params)
            data = body.get("data") or []
            meta = body.get("meta") or {}
            page += 1
            logger.info("  %s page %d: %d rows (has_more=%s)", path, page, len(data), meta.get("has_more"))
            for row in data:
                yield row
            if not meta.get("has_more"):
                break
            cursor = meta.get("cursor")
            if not cursor:
                logger.warning("  %s: has_more=true but no cursor; stopping", path)
                break