"""
Task 12 - locator strategies, turned into real pytest tests (assert-based)
instead of print statements. Uses the shared chrome_driver fixture.

Both phptravels.com/demo and phptravels.com/blog were redesigned since the
assignment screenshots were taken (checked live 2026-09-22) - field names
and classes changed. phptravels.org/register.php still matches closely.
The locators below are REAL and CURRENT (verified live), proven by
actually finding each element.
"""

from selenium.webdriver.common.by import By
from selenium.webdriver.support.relative_locator import locate_with


def test_class_name_locators(chrome_driver):
    chrome_driver.get("https://phptravels.com/demo")

    first_name = chrome_driver.find_element(By.CLASS_NAME, "first_name")
    assert first_name.tag_name == "input"

    last_name = chrome_driver.find_element(By.CLASS_NAME, "last_name")
    assert last_name.tag_name == "input"


def test_id_locators(chrome_driver):
    chrome_driver.get("https://phptravels.org/register.php")

    first_name_id = chrome_driver.find_element(By.ID, "inputFirstName")
    assert first_name_id.tag_name == "input"

    email_id = chrome_driver.find_element(By.ID, "inputEmail")
    assert email_id.tag_name == "input"


def test_name_locators(chrome_driver):
    chrome_driver.get("https://phptravels.org/register.php")

    first_name_by_name = chrome_driver.find_element(By.NAME, "firstname")
    assert first_name_by_name.tag_name == "input"

    email_by_name = chrome_driver.find_element(By.NAME, "email")
    assert email_by_name.tag_name == "input"


def test_css_selector_locators(chrome_driver):
    chrome_driver.get("https://phptravels.org/register.php")
    submit_by_id_css = chrome_driver.find_element(By.CSS_SELECTOR, "#inputFirstName")
    assert submit_by_id_css.tag_name == "input"

    chrome_driver.get("https://phptravels.com/demo")
    submit_btn_css = chrome_driver.find_element(By.CSS_SELECTOR, ".btn_submit")
    assert submit_btn_css.tag_name == "button"


def test_xpath_locators(chrome_driver):
    # NOTE: By.CLASS_NAME matches if the class is ONE OF several classes on
    # the element (token match). Plain XPath [@class='x'] requires the WHOLE
    # class attribute to equal exactly 'x' - it fails if other classes are
    # mixed in. contains(@class, 'x') is the XPath way to get the same
    # "one of several classes" behavior as By.CLASS_NAME.
    chrome_driver.get("https://phptravels.com/demo")
    first_name_xpath = chrome_driver.find_element(
        By.XPATH, "//input[contains(@class, 'first_name')]"
    )
    assert first_name_xpath.tag_name == "input"

    chrome_driver.get("https://phptravels.org/register.php")
    email_id_xpath = chrome_driver.find_element(By.XPATH, "//input[@id='inputEmail']")
    assert email_id_xpath.tag_name == "input"


def test_relative_locator(chrome_driver):
    # register.php "Billing Address": Postcode sits to the right of State
    # in the same row.
    chrome_driver.get("https://phptravels.org/register.php")
    postcode = chrome_driver.find_element(
        locate_with(By.TAG_NAME, "input").to_right_of({By.ID: "stateinput"})
    )
    assert postcode.get_attribute("id") is not None
