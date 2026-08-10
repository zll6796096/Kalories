from __future__ import annotations

from collections.abc import Callable
from math import isfinite
from threading import Lock
from time import monotonic


class TokenBucket:
    def __init__(
        self,
        *,
        capacity: float,
        refill_per_second: float,
        clock: Callable[[], float] = monotonic,
    ) -> None:
        if (
            not isfinite(capacity)
            or capacity <= 0
            or not isfinite(refill_per_second)
            or refill_per_second <= 0
        ):
            raise ValueError("capacity and refill rate must be positive and finite")

        self._capacity = float(capacity)
        self._refill_per_second = float(refill_per_second)
        self._clock = clock
        self._tokens = float(capacity)
        self._updated_at = clock()
        self._lock = Lock()

    def try_acquire(self) -> bool:
        with self._lock:
            now = self._clock()
            elapsed = max(0.0, now - self._updated_at)
            self._tokens = min(
                self._capacity,
                self._tokens + elapsed * self._refill_per_second,
            )
            self._updated_at = max(self._updated_at, now)

            if self._tokens < 1:
                return False

            self._tokens -= 1
            return True
