from concurrent.futures import ThreadPoolExecutor
import math
from threading import Barrier
import unittest

from lib.rate_limit import TokenBucket


class FakeClock:
    def __init__(self) -> None:
        self.value = 0.0

    def __call__(self) -> float:
        return self.value


class TokenBucketTests(unittest.TestCase):
    def test_allows_burst_then_refills_at_twelve_per_minute(self) -> None:
        clock = FakeClock()
        bucket = TokenBucket(
            capacity=4,
            refill_per_second=12 / 60,
            clock=clock,
        )

        self.assertEqual(
            [True, True, True, True, False],
            [bucket.try_acquire() for _ in range(5)],
        )

        clock.value = 5.0
        self.assertTrue(bucket.try_acquire())
        self.assertFalse(bucket.try_acquire())

    def test_simultaneous_callers_cannot_exceed_capacity(self) -> None:
        participants = 32
        clock = FakeClock()
        bucket = TokenBucket(capacity=4, refill_per_second=1, clock=clock)
        start = Barrier(participants)

        def acquire_at_once() -> bool:
            start.wait(timeout=10)
            return bucket.try_acquire()

        with ThreadPoolExecutor(max_workers=participants) as executor:
            futures = [executor.submit(acquire_at_once) for _ in range(participants)]
            results = [future.result(timeout=10) for future in futures]

        self.assertEqual(results.count(True), 4)
        self.assertEqual(results.count(False), participants - 4)

    def test_clock_moving_backwards_never_adds_tokens(self) -> None:
        clock = FakeClock()
        clock.value = 100.0
        bucket = TokenBucket(capacity=1, refill_per_second=1, clock=clock)

        self.assertTrue(bucket.try_acquire())
        for timestamp in (-100.0, -99.0, 99.0, 100.0):
            with self.subTest(timestamp=timestamp):
                clock.value = timestamp
                self.assertFalse(bucket.try_acquire())

        clock.value = 101.0
        self.assertTrue(bucket.try_acquire())

    def test_long_clock_jump_refill_is_capped_at_capacity(self) -> None:
        clock = FakeClock()
        bucket = TokenBucket(capacity=4, refill_per_second=1, clock=clock)

        self.assertEqual(
            [True, True, True, True, False],
            [bucket.try_acquire() for _ in range(5)],
        )

        clock.value = 10_000.0
        self.assertEqual(
            [True, True, True, True, False],
            [bucket.try_acquire() for _ in range(5)],
        )

    def test_partial_refill_requires_the_full_token_threshold(self) -> None:
        for elapsed, expected in ((1.5, False), (2.0, True), (2.5, True)):
            with self.subTest(elapsed=elapsed):
                clock = FakeClock()
                bucket = TokenBucket(
                    capacity=1,
                    refill_per_second=0.5,
                    clock=clock,
                )
                self.assertTrue(bucket.try_acquire())

                clock.value = elapsed

                self.assertEqual(bucket.try_acquire(), expected)

    def test_nonpositive_configuration_fails_closed(self) -> None:
        for capacity in (0, -1):
            with self.subTest(capacity=capacity):
                with self.assertRaises(ValueError):
                    TokenBucket(capacity=capacity, refill_per_second=1)

        for refill_per_second in (0, -1):
            with self.subTest(refill_per_second=refill_per_second):
                with self.assertRaises(ValueError):
                    TokenBucket(capacity=1, refill_per_second=refill_per_second)

    def test_nonfinite_configuration_fails_closed(self) -> None:
        for capacity in (math.nan, math.inf, -math.inf):
            with self.subTest(capacity=capacity):
                with self.assertRaises(ValueError):
                    TokenBucket(capacity=capacity, refill_per_second=1)

        for refill_per_second in (math.nan, math.inf, -math.inf):
            with self.subTest(refill_per_second=refill_per_second):
                with self.assertRaises(ValueError):
                    TokenBucket(capacity=1, refill_per_second=refill_per_second)


if __name__ == "__main__":
    unittest.main()
