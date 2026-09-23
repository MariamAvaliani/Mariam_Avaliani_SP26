"""
Task 3 - Locators for the elements highlighted in the assignment screenshots.

IMPORTANT NOTE (read this first): both phptravels.com/demo and
phptravels.com/blog have been redesigned since the assignment screenshots
were taken (checked live on 2026-09-22) - field names, classes and even the
whole page layout changed. phptravels.org/register.php, however, still
matches the screenshot closely, so those locators below are exact.
For the two changed pages, the locators below are REAL and CURRENT (taken
from the live site today), but they point at the *current* version of the
page, not necessarily the exact red-highlighted box in your screenshot.
Before you submit, open the real assignment page yourself (F12 ->
Elements) and check these against what you actually see - if the page
still looks like your screenshot, they will match as-is.

Each locator is proven by actually finding the element with Selenium below.
"""

from selenium import webdriver
from selenium.webdriver.common.by import By
from selenium.webdriver.support.relative_locator import locate_with

driver = webdriver.Chrome()
driver.implicitly_wait(5)

try:
    # =====================================================================
    # 1) CLASS NAME (2 examples) - phptravels.com/demo, "Instant Demo
    #    Request Form" (current live version of the highlighted form)
    # =====================================================================
    driver.get("https://phptravels.com/demo")

    first_name = driver.find_element(By.CLASS_NAME, "first_name")
    print("class name #1 -> first_name field found:", first_name.tag_name)

    last_name = driver.find_element(By.CLASS_NAME, "last_name")
    print("class name #2 -> last_name field found:", last_name.tag_name)

    # =====================================================================
    # 2) ID (2 examples) - phptravels.org/register.php,
    #    "Personal Information" box (still matches the screenshot)
    # =====================================================================
    driver.get("https://phptravels.org/register.php")

    first_name_id = driver.find_element(By.ID, "inputFirstName")
    print("id #1 -> inputFirstName found:", first_name_id.tag_name)

    email_id = driver.find_element(By.ID, "inputEmail")
    print("id #2 -> inputEmail found:", email_id.tag_name)

    # =====================================================================
    # 3) NAME (2 examples) - same register.php form
    # =====================================================================
    first_name_by_name = driver.find_element(By.NAME, "firstname")
    print("name #1 -> firstname found:", first_name_by_name.tag_name)

    email_by_name = driver.find_element(By.NAME, "email")
    print("name #2 -> email found:", email_by_name.tag_name)

    # =====================================================================
    # 4) CSS SELECTOR (2 examples)
    # =====================================================================
    submit_by_id_css = driver.find_element(By.CSS_SELECTOR, "#inputFirstName")
    print("css #1 -> #inputFirstName found:", submit_by_id_css.tag_name)

    driver.get("https://phptravels.com/demo")
    submit_btn_css = driver.find_element(By.CSS_SELECTOR, ".btn_submit")
    print("css #2 -> .btn_submit found:", submit_btn_css.tag_name)

    # =====================================================================
    # 5) XPATH (2 examples)
    # NOTE: By.CLASS_NAME matches if the class is ONE OF several classes on
    # the element (token match). Plain XPath [@class='x'] requires the WHOLE
    # class attribute to equal exactly 'x' - it fails if other classes are
    # mixed in. contains(@class, 'x') is the XPath way to get the same
    # "one of several classes" behavior as By.CLASS_NAME.
    # =====================================================================
    first_name_xpath = driver.find_element(
        By.XPATH, "//input[contains(@class, 'first_name')]"
    )
    print("xpath #1 -> input[contains(@class,'first_name')] found:", first_name_xpath.tag_name)

    driver.get("https://phptravels.org/register.php")
    email_id_xpath = driver.find_element(By.XPATH, "//input[@id='inputEmail']")
    print("xpath #2 -> input[@id='inputEmail'] found:", email_id_xpath.tag_name)

    # =====================================================================
    # 6*) RELATIVE LOCATOR (1 example) - register.php "Billing Address":
    #     Postcode sits to the right of State in the same row.
    # =====================================================================
    postcode = driver.find_element(
        locate_with(By.TAG_NAME, "input").to_right_of({By.ID: "stateinput"})
    )
    print("relative -> input to the right of #stateinput found:", postcode.get_attribute("id"))

finally:
    driver.quit()


# ---------------------------------------------------------------------
# Answer table (for the write-up / screenshot), pages used:
#   A) https://phptravels.com/demo            (Instant Demo Request Form)
#   B) https://phptravels.org/register.php    (Personal Information / Billing Address)
#
# 1. class name
#    find_element(By.CLASS_NAME, "first_name")      -> page A
#    find_element(By.CLASS_NAME, "last_name")       -> page A
# 2. id
#    find_element(By.ID, "inputFirstName")          -> page B
#    find_element(By.ID, "inputEmail")               -> page B
# 3. name
#    find_element(By.NAME, "firstname")              -> page B
#    find_element(By.NAME, "email")                  -> page B
# 4. CSS selector
#    find_element(By.CSS_SELECTOR, "#inputFirstName") -> page B
#    find_element(By.CSS_SELECTOR, ".btn_submit")      -> page A
# 5. XPath
#    find_element(By.XPATH, "//input[contains(@class,'first_name')]") -> page A
#    find_element(By.XPATH, "//input[@id='inputEmail']") -> page B
# 6*. Relative locator
#    locate_with(By.TAG_NAME, "input").to_right_of({By.ID: "stateinput"}) -> page B (finds Postcode)
# ---------------------------------------------------------------------
