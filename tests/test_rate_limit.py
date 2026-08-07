import math
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

    def test_clock_moving_backwards_never_adds_tokens(self) -> None:
        clock = FakeClock()
        bucket = TokenBucket(capacity=1, refill_per_second=1, clock=clock)

        self.assertTrue(bucket.try_acquire())
        clock.value = -100.0

        self.assertFalse(bucket.try_acquire())

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
