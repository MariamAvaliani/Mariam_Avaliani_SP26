import allure
import pytest


def run_check(db_connection, sql_cases, case_name):
    """
    Looks up one named case from the parametrized config (requirement #4),
    runs its SQL through the shared DB connection fixture (requirement #5)
    and asserts the result, with each step logged to Allure.
    """
    case = next(c for c in sql_cases if c["name"] == case_name)

    with allure.step(f"Run query for '{case_name}': {case['sql']}"):
        db_connection.execute(case["sql"])
        result = db_connection.fetchone()[0]

    with allure.step(f"Assert result == expected ({case['expected']})"):
        assert result == case["expected"], (
            f"{case_name} failed: got {result}, expected {case['expected']}"
        )


# ---------------------- SMOKE: do the objects exist? ----------------------

@allure.title("DWH_CLIENTS table exists")
@pytest.mark.smoke
def test_dwh_clients_table_exists(db_connection, sql_cases):
    run_check(db_connection, sql_cases, "table_exists_dwh_clients")


@allure.title("DWH_PRODUCTS table exists")
@pytest.mark.smoke
def test_dwh_products_table_exists(db_connection, sql_cases):
    run_check(db_connection, sql_cases, "table_exists_dwh_products")


@allure.title("DM_MAIN_DASHBOARD table exists")
@pytest.mark.smoke
def test_dm_main_dashboard_table_exists(db_connection, sql_cases):
    run_check(db_connection, sql_cases, "table_exists_dm_main_dashboard")


# ---------------------- CRITICAL: is the data healthy? ----------------------

@allure.title("DWH_CLIENTS is not empty")
@pytest.mark.critical
def test_dwh_clients_not_empty(db_connection, sql_cases):
    run_check(db_connection, sql_cases, "dwh_clients_is_not_empty")


@allure.title("DWH_PRODUCTS has no NULL product_id")
@pytest.mark.critical
def test_dwh_products_no_null_ids(db_connection, sql_cases):
    run_check(db_connection, sql_cases, "dwh_products_has_no_null_product_id")


@allure.title("DM_MAIN_DASHBOARD has no duplicate ids")
@pytest.mark.critical
def test_dm_main_dashboard_no_duplicates(db_connection, sql_cases):
    run_check(db_connection, sql_cases, "dm_main_dashboard_has_no_duplicate_ids")
