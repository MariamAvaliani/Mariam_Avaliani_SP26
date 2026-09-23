"""
Task 12 - Chrome (automatic driver) vs Firefox (manual driver), turned into
real pytest tests instead of a plain script.

1) Chrome  -> AUTOMATIC driver approach (Selenium Manager).
   Selenium 4.6+ ships Selenium Manager, which finds/downloads the right
   ChromeDriver for the installed Chrome version by itself - no driver path
   to configure. Uses the shared chrome_driver fixture from conftest.py.

2) Firefox -> MANUAL driver approach.
   You download geckodriver yourself and either put it on PATH or hard-code
   its location. If geckodriver isn't set up on this machine yet, the test
   skips itself with a clear message instead of failing the whole run -
   see GECKODRIVER_PATH below.
   Download geckodriver: https://github.com/mozilla/geckodriver/releases
"""

import os

import pytest
from selenium import webdriver
from selenium.webdriver.firefox.service import Service as FirefoxService

# Edit this to where you actually downloaded geckodriver, e.g.:
#   "C:/Users/Mariam/Desktop/geckodriver.exe"
GECKODRIVER_PATH = "/usr/local/bin/geckodriver"


def test_chrome_opens_google_automatic_driver(chrome_driver):
    chrome_driver.get("https://www.google.com")
    assert "Google" in chrome_driver.title


def test_firefox_opens_google_manual_driver():
    if not os.path.exists(GECKODRIVER_PATH):
        pytest.skip(
            f"geckodriver not found at {GECKODRIVER_PATH} - download it and "
            "update GECKODRIVER_PATH at the top of this file to run this test."
        )

    firefox_service = FirefoxService(executable_path=GECKODRIVER_PATH)
    firefox_driver = webdriver.Firefox(service=firefox_service)
    try:
        firefox_driver.get("https://www.google.com")
        assert "Google" in firefox_driver.title
    finally:
        firefox_driver.quit()
