"""
Shared pytest fixtures for Task 1 (API + bucket smoke test).

The AWS fixture uses `moto` to mock S3 so the test is runnable without real
AWS credentials (moto: pip install moto). The GCP fixture uses a small fake
client (unittest.mock) since there is no lightweight built-in GCS emulator -
in a real project you would replace it with a real
`google.cloud.storage.Client()` pointed at your actual bucket/service
account.
"""

import datetime
from unittest.mock import MagicMock

import boto3
import pytest
from moto import mock_aws


@pytest.fixture
def test_date():
    """The date we are checking data for, e.g. '2026-09-22'."""
    return datetime.date.today().isoformat()


@pytest.fixture
def aws_client(test_date):
    """
    Real AWS usage:
        return boto3.client("s3", region_name="eu-west-1")
    Here we mock S3 with moto so the smoke test can run without credentials,
    and pre-seed the staging bucket with one object for `test_date` so the
    test has something real to find.
    """
    with mock_aws():
        client = boto3.client("s3", region_name="eu-west-1")
        client.create_bucket(
            Bucket="my-staging-bucket",
            CreateBucketConfiguration={"LocationConstraint": "eu-west-1"},
        )
        client.put_object(
            Bucket="my-staging-bucket",
            Key=f"{test_date}/data.csv",
            Body=b"col1,col2\n1,2\n",
        )
        yield client


@pytest.fixture
def gcp_client(test_date):
    """
    Real GCP usage:
        from google.cloud import storage
        return storage.Client()  # needs GOOGLE_APPLICATION_CREDENTIALS
    Here we fake the interface we actually use (`list_blobs`) so the test
    is runnable without a real GCP project.
    """
    fake_blob = MagicMock()
    fake_blob.name = f"{test_date}/data.csv"

    client = MagicMock()
    client.list_blobs.return_value = [fake_blob]
    return client
