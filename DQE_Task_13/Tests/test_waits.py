"""
Task 12 - implicit wait + explicit wait, turned into a real pytest test.

Implicit wait is set once, globally, on the driver (see the chrome_driver
fixture in conftest.py: driver.implicitly_wait(5)) - every find_element
call after that keeps polling for up to 5 seconds before giving up.
Explicit wait is used at one specific, trickier step (waiting for the
DuckDuckGo results to actually appear after the search).

(google.com was tried first, but Google's bot-detection blocked the
automated browser with a reCAPTCHA - a common real-world Selenium issue,
not a bug in this code. DuckDuckGo does not do this.)
"""

from selenium.webdriver.common.by import By
from selenium.webdriver.common.keys import Keys
from selenium.webdriver.support.ui import WebDriverWait
from selenium.webdriver.support import expected_conditions as EC


def test_search_and_open_first_result(chrome_driver):
    chrome_driver.get("https://duckduckgo.com")

    search_box = chrome_driver.find_element(By.NAME, "q")
    search_box.send_keys("Selenium")
    search_box.send_keys(Keys.RETURN)

    # explicit wait: wait specifically for the results to appear
    wait = WebDriverWait(chrome_driver, 10)
    results = wait.until(
        EC.presence_of_element_located((By.CSS_SELECTOR, 'article[data-testid="result"]'))
    )

    first_link = results.find_element(By.CSS_SELECTOR, "h2 a")
    href = first_link.get_attribute("href")
    assert href, "First result link has no href"

    first_link.click()
    assert chrome_driver.title, "Page title should not be empty after clicking the first result"
