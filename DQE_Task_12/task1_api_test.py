"""
Task 1 - API testing with requests + pytest
--------------------------------------------
Scenario 1: create 10 posts for user with Id=3 (JSONPlaceholder fake REST API)
            and verify that 10 posts exist for that user.
Scenario 2: verify that, for a given date, the GCP source bucket and the AWS
            staging (target) bucket both contain data (a basic "not empty"
            smoke test for a GCP -> AWS migration).

Run with:
    pytest task1_api_test.py --alluredir=allure-results -v
    allure serve allure-results
"""

import pytest
import requests

BASE_URL = "https://jsonplaceholder.typicode.com"
USER_ID = 3


# ---------- Scenario 1: API / requests ----------

class TestUserPosts:
    """
    NOTE for Mariam: JSONPlaceholder is a *fake* REST API used for practice.
    It accepts POST requests and answers with a realistic response (id 101),
    but it does NOT actually save anything on the server. That is why the
    test does not rely on "my POSTs must now exist" - instead it:
      1) sends 10 POST requests and checks each one succeeds (201 Created)
      2) checks that GET /posts?userId=3 already returns 10 posts
         (JSONPlaceholder's fixed test dataset always has 10 posts per user)
    This is exactly the kind of test you would also run for real against a
    real API once you replace BASE_URL with your own backend.
    """

    def test_create_10_posts_for_user(self):
        created_ids = []
        for i in range(10):
            payload = {
                "title": f"post {i}",
                "body": "created by automated test",
                "userId": USER_ID,
            }
            response = requests.post(f"{BASE_URL}/posts", json=payload)
            assert response.status_code == 201, (
                f"Expected 201 Created, got {response.status_code}"
            )
            created_ids.append(response.json()["id"])

        assert len(created_ids) == 10

    def test_10_posts_exist_for_user(self):
        response = requests.get(f"{BASE_URL}/posts", params={"userId": USER_ID})
        assert response.status_code == 200

        posts = response.json()
        assert len(posts) == 10, (
            f"Expected 10 posts for user {USER_ID}, found {len(posts)}"
        )
        assert all(post["userId"] == USER_ID for post in posts)


# ---------- Scenario 2: GCP -> AWS bucket smoke test ----------

class TestBucketDataPresence:
    """
    Smoke test: for a given date, both the GCP source bucket and the AWS
    staging (target) bucket must contain at least one object.

    Real cloud credentials are required to run this against real buckets.
    The `gcp_client` and `aws_client` fixtures live in conftest.py; swap the
    fake/mocked clients used there for real `google-cloud-storage` /
    `boto3` clients (with real credentials) when you point this at your
    actual project buckets.
    """

    def test_gcp_source_bucket_not_empty(self, gcp_client, test_date):
        blobs = list(gcp_client.list_blobs(prefix=test_date))
        assert len(blobs) > 0, f"GCP source bucket has no data for {test_date}"

    def test_aws_target_bucket_not_empty(self, aws_client, test_date):
        response = aws_client.list_objects_v2(
            Bucket="my-staging-bucket", Prefix=test_date
        )
        assert response.get("KeyCount", 0) > 0, (
            f"AWS staging bucket has no data for {test_date}"
        )
