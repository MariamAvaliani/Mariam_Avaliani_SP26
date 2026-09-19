import shutil
import subprocess

import psycopg2
import pytest
import yaml


# ---------- global config (loaded once per session) ----------

@pytest.fixture(scope="session")
def sql_cases():
    """Loads all SQL check definitions from the config file (requirement #4)."""
    with open("config/sql_config.yaml", "r") as stream:
        config = yaml.safe_load(stream)
    return config["tests"]


# ---------- DB connection fixture (requirement #5) ----------

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


# ---------- bonus: auto-generate the Allure HTML report (requirement #7*) ----------

def pytest_sessionfinish(session, exitstatus):
    """
    Runs once, right after the whole pytest session finishes.
    If tests were launched with --alluredir=<folder>, this automatically
    builds a single-file HTML report out of those raw results, so you
    don't have to run the `allure generate` command by hand every time.
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
