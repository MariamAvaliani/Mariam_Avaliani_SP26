import time

import pytest


@pytest.fixture(scope="module", autouse=True)
def track_suite_time():
    """
    Tracks the execution time of the WHOLE suite (this module).
    autouse=True + scope="module" => pytest creates this fixture exactly
    once for the module, before the first test, and tears it down once,
    after the last test - regardless of how many tests are in the file.
    """
    suite_start = time.time()
    print("\n[SUITE] started")
    yield
    suite_end = time.time()
    print(f"\n[SUITE] finished. Total suite execution time: {suite_end - suite_start:.2f} sec")


@pytest.fixture()
def track_test_time():
    """
    Tracks the execution time of a SINGLE test.
    Default scope ("function") => a fresh instance runs for every test
    that requests it, so each test gets its own individual timing.
    """
    test_start = time.time()
    yield
    test_end = time.time()
    print(f"[TEST] execution time: {test_end - test_start:.2f} sec")


def add_numbers(a, b):
    return a + b


# --- All tests below use track_test_time, EXCEPT the last one ---

def test_add_two_positive_numbers(track_test_time):
    a, b = 3, 5
    result = add_numbers(a, b)
    time.sleep(2)
    assert result == 8, f"add_numbers({a}, {b}) returned {result}, expected 8"


def test_add_two_negative_numbers(track_test_time):
    a, b = -3, -5
    result = add_numbers(a, b)
    time.sleep(3)
    assert result == -8, f"add_numbers({a}, {b}) returned {result}, expected -8"


def test_add_negative_and_positive_numbers():
    # last test - intentionally does NOT use track_test_time
    a, b = -3, 5
    result = add_numbers(a, b)
    time.sleep(10)
    assert result == 2, f"add_numbers({a}, {b}) returned {result}, expected 2"
