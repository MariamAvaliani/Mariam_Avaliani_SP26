"""
Task 4 - Implicit wait + explicit wait.

1) Open duckduckgo.com
2) Type "Selenium" into the search field
3) Open the first result

(Google.com itself was tried first, but Google's bot-detection blocked the
automated browser with a reCAPTCHA - a very common real-world issue with
Selenium, not a bug in this code. DuckDuckGo does not do this, so it is
used here instead; the implicit/explicit wait logic is identical either
way.)

Implicit wait is set once, globally, on the driver: for every findElement
call afterwards, WebDriver will keep polling the DOM for up to that many
seconds before giving up. Explicit wait is used at one specific, trickier
step (waiting for the results list to actually appear after the search).
"""

from selenium import webdriver
from selenium.webdriver.common.by import By
from selenium.webdriver.common.keys import Keys
from selenium.webdriver.support.ui import WebDriverWait
from selenium.webdriver.support import expected_conditions as EC

driver = webdriver.Chrome()

try:
    # ---- implicit wait: applies to every find_element call below ----
    driver.implicitly_wait(5)

    driver.get("https://duckduckgo.com")

    search_box = driver.find_element(By.NAME, "q")
    search_box.send_keys("Selenium")
    search_box.send_keys(Keys.RETURN)

    # ---- explicit wait: wait specifically for the results to appear ----
    wait = WebDriverWait(driver, 10)
    results = wait.until(
        EC.presence_of_element_located((By.CSS_SELECTOR, 'article[data-testid="result"]'))
    )

    first_link = results.find_element(By.CSS_SELECTOR, "h2 a")
    print("Opening:", first_link.get_attribute("href"))
    first_link.click()

    print("Landed on:", driver.title)

finally:
    driver.quit()
