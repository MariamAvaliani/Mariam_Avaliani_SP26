"""
Shared pytest fixtures for the whole framework.

Where each group of fixtures came from:
  - sql_cases / db_connection      -> Task 6 (DWH testing, test_db_tables.py)
  - test_date / aws_client / gcp_client -> Task 12 (test_api_and_buckets.py)
  - chrome_driver                  -> new, shared by the Selenium test
                                       modules (test_locators.py,
                                       test_waits.py, test_browser_drivers.py)
  - pytest_sessionfinish            -> Task 6 (auto-builds the Allure HTML
                                       report after the run, if Allure CLI
                                       is on PATH)

track_suite_time / track_test_time (from the fixtures lesson) are NOT here
on purpose - they are autouse=True at module scope, meaning "wrap every
test in this one file". Moving them here would silently start timing every
test in the whole framework, which isn't what that lesson was demonstrating.
They stay local to test_fixtures_demo.py.
"""

import datetime
import shutil
import subprocess
from unittest.mock import MagicMock

import boto3
import psycopg2
import pytest
import yaml
from moto import mock_aws
from selenium import webdriver


# ---------- DWH / DB fixtures (Task 6) ----------

@pytest.fixture(scope="session")
def sql_cases():
    """Loads all SQL check definitions from Configs/sql_config.yaml."""
    with open("Configs/sql_config.yaml", "r") as stream:
        config = yaml.safe_load(stream)
    return config["tests"]


@pytest.fixture(scope="session")
def db_connection():
    """
    Opens one DB connection/cursor for the whole test session and closes it
    as a teardown step (after yield) once all tests are done.
    Adjust the credentials below to match your own local DB.
    """
    conn = psycopg2.connect(
        database="dwh_hw_db",
        user="postgres",
        password="postgres",
        host="localhost",
        port="5433",
    )
    cursor = conn.cursor()
    yield cursor
    cursor.close()
    conn.close()


# ---------- API + cloud bucket fixtures (Task 12) ----------

@pytest.fixture
def test_date():
    """The date we are checking data for, e.g. '2026-09-23'."""
    return datetime.date.today().isoformat()


@pytest.fixture
def aws_client(test_date):
    """
    Real AWS usage:
        return boto3.client("s3", region_name="eu-west-1")
    Here we mock S3 with moto so the smoke test can run without credentials,
    and pre-seed the staging bucket with one object for `test_date`.
    """
    with mock_aws():
        client = boto3.client("s3", region_name="eu-west-1")
        client.create_bucket(
            Bucket="my-staging-bucket",
            CreateBucketConfiguration={"LocationConstraint": "eu-west-1"},
        )
        client.put_object(
            Bucket="my-staging-bucket",
            Key=f"{test_date}/data.csv",
            Body=b"col1,col2\n1,2\n",
        )
        yield client


@pytest.fixture
def gcp_client(test_date):
    """
    Real GCP usage:
        from google.cloud import storage
        return storage.Client()  # needs GOOGLE_APPLICATION_CREDENTIALS
    Here we fake the interface we actually use (`list_blobs`).
    """
    fake_blob = MagicMock()
    fake_blob.name = f"{test_date}/data.csv"

    client = MagicMock()
    client.list_blobs.return_value = [fake_blob]
    return client


# ---------- Shared Selenium driver (used by the browser test modules) ----------

@pytest.fixture
def chrome_driver():
    """One Chrome session per test that asks for it; always quit afterwards."""
    driver = webdriver.Chrome()
    driver.implicitly_wait(5)
    yield driver
    driver.quit()


# ---------- bonus: auto-generate the Allure HTML report (Task 6) ----------

def pytest_sessionfinish(session, exitstatus):
    """
    Runs once, right after the whole pytest session finishes.
    If tests were launched with --alluredir=<folder>, this automatically
    builds a single-file HTML report out of those raw results.
    """
    alluredir = session.config.option.allure_report_dir
    if not alluredir:
        return
    report_dir = f"{alluredir}-html"

    # On Windows, npm-installed CLI tools like "allure" are .cmd/.bat shims,
    # which subprocess.run() won't resolve from a bare name. shutil.which()
    # correctly resolves the .cmd/.bat/.exe extension on any OS.
    allure_path = shutil.which("allure")
    if allure_path is None:
        print(
            "\n[allure] 'allure' command not found on PATH - skipping HTML report "
            "generation. Install the Allure CLI to enable this step, or run "
            "'allure generate' manually once it's installed."
        )
        return

    try:
        subprocess.run(
            [allure_path, "generate", alluredir, "-o", report_dir, "--single-file", "--clean"],
            check=False,
        )
    except OSError as exc:
        print(f"\n[allure] Could not run 'allure generate': {exc}")
