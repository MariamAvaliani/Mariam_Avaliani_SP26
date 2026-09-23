"""
Task 13, Home Task 2 - 2 UI checks for the Power BI report.

Target: the Power BI Playground's "Capture report views" showcase
(https://playground.powerbi.com/en-us/showcases-gallery/capture-report-views)
- see the note in Configs/config_selenium.yaml for why this target is used
instead of the skeleton's original Microsoft Investor Relations page (that
page's Power BI tab no longer exists - checked live, 2026-09-23).

Check 1: a real button ("Capture view") is present in the report toolbar.
Check 2: a real chart title ("Total Category Volume Over Time by Region")
         is present, AND the chart actually drew at least one bar - this
         covers the assignment's "titles ... or the presence of some bar"
         with one test.

Run with:
    pytest Tests/test_powerbi_report.py --alluredir=allure-results -v
"""

import os

import allure
import pytest
import yaml
from selenium import webdriver

from Pages.capture_report_views_page import CaptureReportViewsPage


def get_selenium_config(config_name):
    module_dir = os.path.dirname(os.path.abspath(__file__))
    parent_dir = os.path.dirname(module_dir)
    with open(os.path.join(parent_dir, "Configs", config_name), "r") as stream:
        config = yaml.safe_load(stream)
    return config["global"]


@pytest.fixture
def open_capture_report_views_page():
    cfg = get_selenium_config("config_selenium.yaml")
    driver = webdriver.Chrome()
    driver.set_window_size(1400, 900)
    driver.get(cfg["report_uri"])

    page = CaptureReportViewsPage(driver, cfg["delay"])
    page.open_report()
    page.switch_to_report_frame()
    yield page
    driver.quit()


@allure.title("Power BI report: 'Capture view' button is present")
@pytest.mark.critical
def test_capture_view_button_present(open_capture_report_views_page):
    page = open_capture_report_views_page
    with allure.step("Look for the 'Capture view' button inside the embedded report"):
        button = page.get_capture_view_button()
    assert button is not None


@allure.title("Power BI report: chart title and bars are present")
@pytest.mark.critical
def test_chart_title_and_bars_present(open_capture_report_views_page):
    page = open_capture_report_views_page
    with allure.step("Look for the chart title 'Total Category Volume Over Time by Region'"):
        title = page.get_chart_title()
    assert title is not None

    with allure.step("Check that at least one bar was actually drawn under that chart"):
        bar_count = page.get_bar_count()
    assert bar_count > 0, "Expected at least one bar in the chart, found none"
