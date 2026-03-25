"""ACM integration tests using boto3."""

import time
import uuid

import pytest


def test_request_certificate(acm_client):
    """Test requesting an ACM certificate."""
    domain_name = f"test-{uuid.uuid4().hex[:8]}.example.com"
    certificate_arn = None

    try:
        response = acm_client.request_certificate(DomainName=domain_name)

        assert response["ResponseMetadata"]["HTTPStatusCode"] == 200
        assert "CertificateArn" in response
        assert response["CertificateArn"].startswith("arn:aws:acm:")
        certificate_arn = response["CertificateArn"]
    finally:
        if certificate_arn:
            acm_client.delete_certificate(CertificateArn=certificate_arn)


def test_request_certificate_with_sans(acm_client):
    """Test requesting a certificate with Subject Alternative Names."""
    domain_name = f"test-{uuid.uuid4().hex[:8]}.example.com"
    sans = [f"www.{domain_name}", f"api.{domain_name}"]
    certificate_arn = None

    try:
        response = acm_client.request_certificate(
            DomainName=domain_name,
            SubjectAlternativeNames=sans,
        )

        assert response["ResponseMetadata"]["HTTPStatusCode"] == 200
        assert "CertificateArn" in response
        certificate_arn = response["CertificateArn"]
    finally:
        if certificate_arn:
            acm_client.delete_certificate(CertificateArn=certificate_arn)


def test_describe_certificate(acm_client, test_certificate):
    """Test describing a certificate."""
    response = acm_client.describe_certificate(CertificateArn=test_certificate)

    assert response["ResponseMetadata"]["HTTPStatusCode"] == 200
    assert "Certificate" in response
    cert = response["Certificate"]
    assert cert["CertificateArn"] == test_certificate
    assert "DomainName" in cert
    assert "Status" in cert


def test_describe_certificate_not_found(acm_client):
    """Test describing a non-existent certificate raises error."""
    fake_arn = "arn:aws:acm:us-east-1:123456789012:certificate/00000000-0000-0000-0000-000000000000"

    with pytest.raises(Exception) as exc_info:
        acm_client.describe_certificate(CertificateArn=fake_arn)

    assert "ResourceNotFoundException" in str(type(exc_info.value).__name__) or "not found" in str(exc_info.value).lower()


def test_list_certificates(acm_client, test_certificate):
    """Test listing certificates."""
    response = acm_client.list_certificates()

    assert response["ResponseMetadata"]["HTTPStatusCode"] == 200
    assert "CertificateSummaryList" in response

    arns = [cert["CertificateArn"] for cert in response["CertificateSummaryList"]]
    assert test_certificate in arns


def test_list_certificates_structure(acm_client):
    """Test listing certificates returns correct structure."""
    response = acm_client.list_certificates()

    assert response["ResponseMetadata"]["HTTPStatusCode"] == 200
    assert "CertificateSummaryList" in response
    assert isinstance(response["CertificateSummaryList"], list)


def test_get_certificate(acm_client, test_certificate):
    """Test getting certificate body and chain.

    Note: This may fail if certificate is still PENDING_VALIDATION.
    The emulator auto-issues certificates after validation wait time.
    """
    # Wait briefly for certificate to be issued (emulator auto-issues)
    time.sleep(1)

    try:
        response = acm_client.get_certificate(CertificateArn=test_certificate)

        assert response["ResponseMetadata"]["HTTPStatusCode"] == 200
        assert "Certificate" in response
        assert response["Certificate"].startswith("-----BEGIN CERTIFICATE-----")

        if "CertificateChain" in response and response["CertificateChain"]:
            assert "-----BEGIN CERTIFICATE-----" in response["CertificateChain"]
    except acm_client.exceptions.RequestInProgressException:
        pytest.skip("Certificate still pending validation")


def test_delete_certificate(acm_client):
    """Test deleting a certificate."""
    domain_name = f"test-delete-{uuid.uuid4().hex[:8]}.example.com"
    create_response = acm_client.request_certificate(DomainName=domain_name)
    certificate_arn = create_response["CertificateArn"]

    response = acm_client.delete_certificate(CertificateArn=certificate_arn)
    assert response["ResponseMetadata"]["HTTPStatusCode"] == 200

    list_response = acm_client.list_certificates()
    arns = [cert["CertificateArn"] for cert in list_response["CertificateSummaryList"]]
    assert certificate_arn not in arns


def test_delete_certificate_not_found(acm_client):
    """Test deleting a non-existent certificate raises error."""
    fake_arn = "arn:aws:acm:us-east-1:123456789012:certificate/00000000-0000-0000-0000-000000000000"

    with pytest.raises(Exception) as exc_info:
        acm_client.delete_certificate(CertificateArn=fake_arn)

    assert "ResourceNotFoundException" in str(type(exc_info.value).__name__) or "not found" in str(exc_info.value).lower()
