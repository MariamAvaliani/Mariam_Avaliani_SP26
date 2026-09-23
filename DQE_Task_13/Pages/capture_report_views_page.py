"""
Page Object for the Power BI Playground's "Capture report views" showcase.

Same pattern as the skeleton's IncomeStatementsReportPage (Pages/), but for
a different target - see Configs/config_selenium.yaml for why.

The report is nested TWO iframes deep:
  1. playground.powerbi.com's own page embeds the showcase in an <iframe>
     (same top-level site, e.g. playground.powerbi.com/showcases/...).
  2. That showcase page embeds the real Power BI report in a SECOND
     <iframe>, hosted on a different domain (app.powerbi.com).

A normal page-JavaScript check cannot read inside iframe #2 at all, because
it is cross-origin (the browser blocks that on purpose). Selenium does not
have this limitation - driver.switch_to.frame() works at the browser
automation level, not the page-JavaScript level, so it can step into a
cross-origin iframe just fine. That is exactly why both switch_to.frame()
calls below are needed, one after another, before we can find anything
inside the actual report.
"""

from selenium.webdriver.support.ui import WebDriverWait as WDW
from selenium.webdriver.support import expected_conditions as EC
from selenium.webdriver.common.by import By


class CaptureReportViewsPage:
    def __init__(self, driver, delay):
        self.driver = driver
        self.delay = delay

        # Real, visible text on the report (confirmed live, 2026-09-23):
        # a "Capture view" button in the toolbar, and a bar chart titled
        # "Total Category Volume Over Time by Region".
        self.capture_view_button = "//*[contains(text(), 'Capture view')]"
        self.chart_title = "//*[contains(text(), 'Total Category Volume Over Time by Region')]"
        self.bar_elements = "rect"

    def open_report(self):
        """Report URI is already loaded by the driver fixture; nothing to click here."""
        WDW(self.driver, self.delay).until(
            EC.presence_of_element_located((By.TAG_NAME, "iframe"))
        )

    def switch_to_report_frame(self):
        """Step through both nested iframes to reach the actual Power BI report."""
        outer_iframe = WDW(self.driver, self.delay).until(
            EC.presence_of_element_located((By.TAG_NAME, "iframe"))
        )
        self.driver.switch_to.frame(outer_iframe)

        inner_iframe = WDW(self.driver, self.delay).until(
            EC.presence_of_element_located((By.TAG_NAME, "iframe"))
        )
        self.driver.switch_to.frame(inner_iframe)

    def get_capture_view_button(self):
        """Check 1: the 'Capture view' button is present (a real UI control)."""
        return WDW(self.driver, self.delay).until(
            EC.presence_of_element_located((By.XPATH, self.capture_view_button))
        )

    def get_chart_title(self):
        """Check 2, part A: the bar chart's title text is present."""
        return WDW(self.driver, self.delay).until(
            EC.presence_of_element_located((By.XPATH, self.chart_title))
        )

    def get_bar_count(self):
        """Check 2, part B: at least one bar is actually drawn under that chart."""
        return len(self.driver.find_elements(By.CSS_SELECTOR, self.bar_elements))
