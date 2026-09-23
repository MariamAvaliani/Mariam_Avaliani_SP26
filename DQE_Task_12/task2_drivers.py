"""
Task 2 - Open google.com in Chrome and Firefox, print the page title.

1) Chrome  -> AUTOMATIC driver approach (Selenium Manager).
   Selenium 4.6+ ships Selenium Manager, which finds/downloads the right
   ChromeDriver for the installed Chrome version by itself - you don't
   configure a driver path at all.

2) Firefox -> MANUAL driver approach.
   You download geckodriver yourself and either:
     a) put it on the system PATH, or
     b) hard-code its location (used below, so the script is self-contained).
   Download geckodriver: https://github.com/mozilla/geckodriver/releases
"""

from selenium import webdriver
from selenium.webdriver.firefox.service import Service as FirefoxService

# ---------- 1) Chrome - automatic driver management ----------

chrome_driver = webdriver.Chrome()  # Selenium Manager resolves the driver
try:
    chrome_driver.get("https://www.google.com")
    print("Chrome page title:", chrome_driver.title)
finally:
    chrome_driver.quit()


# ---------- 2) Firefox - manual driver management ----------

# Option A (hard-coded location) - edit this path to where you downloaded it:
GECKODRIVER_PATH = "/usr/local/bin/geckodriver"

firefox_service = FirefoxService(executable_path=GECKODRIVER_PATH)
firefox_driver = webdriver.Firefox(service=firefox_service)

# Option B (PATH variable) - if geckodriver is already on PATH, this is all
# you need instead of Option A:
#   firefox_driver = webdriver.Firefox()

try:
    firefox_driver.get("https://www.google.com")
    print("Firefox page title:", firefox_driver.title)
finally:
    firefox_driver.quit()
