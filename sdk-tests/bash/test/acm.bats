#!/usr/bin/env bats
# ACM integration tests using AWS CLI and bats-core

load 'test_helper/common-setup'

# Track certificates created in this test file for cleanup
CREATED_CERTS=()

setup_file() {
    # Check connectivity to floci
    if ! curl -sf "$AWS_ENDPOINT_URL" > /dev/null 2>&1; then
        echo "Cannot connect to floci at $AWS_ENDPOINT_URL" >&3
        echo "Make sure floci is running before running tests." >&3
        return 1
    fi

    # Generate unique domain suffix for this test run
    export DOMAIN_SUFFIX="test-$(cat /proc/sys/kernel/random/uuid | cut -c1-8 | tr '[:upper:]' '[:lower:]').example.com"
}

teardown_file() {
    # Clean up all tracked certificates
    for cert_arn in "${CREATED_CERTS[@]}"; do
        aws acm delete-certificate --certificate-arn "$cert_arn" 2>/dev/null || true
    done
}

# Helper function to track created certificates
track_certificate() {
    CREATED_CERTS+=("$1")
}

# ============================================
# Test Cases
# ============================================

@test "ACM: request certificate" {
    local domain_name="request-$(date +%s).${DOMAIN_SUFFIX}"

    run aws acm request-certificate --domain-name "$domain_name"
    assert_success

    # Extract ARN from response
    local cert_arn=$(echo "$output" | jq -r '.CertificateArn')
    assert [ -n "$cert_arn" ]
    assert [ "$cert_arn" != "null" ]

    # Verify ARN format
    [[ "$cert_arn" =~ ^arn:aws:acm: ]] || fail "Invalid ARN format: $cert_arn"

    # Cleanup
    aws acm delete-certificate --certificate-arn "$cert_arn" 2>/dev/null || true
}

@test "ACM: request certificate with SANs" {
    local domain_name="san-$(date +%s).${DOMAIN_SUFFIX}"
    local san1="www.${domain_name}"
    local san2="api.${domain_name}"

    run aws acm request-certificate \
        --domain-name "$domain_name" \
        --subject-alternative-names "$san1" "$san2"
    assert_success

    local cert_arn=$(echo "$output" | jq -r '.CertificateArn')
    assert [ -n "$cert_arn" ]
    assert [ "$cert_arn" != "null" ]

    # Cleanup
    aws acm delete-certificate --certificate-arn "$cert_arn" 2>/dev/null || true
}

@test "ACM: describe certificate" {
    local domain_name="describe-$(date +%s).${DOMAIN_SUFFIX}"

    # Create certificate first
    local create_output=$(aws acm request-certificate --domain-name "$domain_name")
    local cert_arn=$(echo "$create_output" | jq -r '.CertificateArn')

    # Describe the certificate
    run aws acm describe-certificate --certificate-arn "$cert_arn"
    assert_success

    # Verify response structure
    run jq -e '.Certificate' <<< "$output"
    assert_success

    run jq -e '.Certificate.CertificateArn' <<< "$output"
    assert_success

    run jq -e '.Certificate.DomainName' <<< "$output"
    assert_success

    run jq -e '.Certificate.Status' <<< "$output"
    assert_success

    # Cleanup
    aws acm delete-certificate --certificate-arn "$cert_arn" 2>/dev/null || true
}

@test "ACM: describe non-existent certificate fails" {
    local fake_arn="arn:aws:acm:us-east-1:123456789012:certificate/00000000-0000-0000-0000-000000000000"

    run aws acm describe-certificate --certificate-arn "$fake_arn"
    assert_failure
}

@test "ACM: list certificates returns CertificateSummaryList" {
    run aws acm list-certificates
    assert_success

    # Verify JSON structure
    run jq -e '.CertificateSummaryList' <<< "$output"
    assert_success
}

@test "ACM: list certificates contains test certificate" {
    local domain_name="list-$(date +%s).${DOMAIN_SUFFIX}"

    # Create certificate first
    local create_output=$(aws acm request-certificate --domain-name "$domain_name")
    local cert_arn=$(echo "$create_output" | jq -r '.CertificateArn')

    # List certificates
    run aws acm list-certificates
    assert_success

    # Find our certificate in the list
    run jq -e ".CertificateSummaryList[] | select(.CertificateArn == \"$cert_arn\")" <<< "$output"
    assert_success

    # Cleanup
    aws acm delete-certificate --certificate-arn "$cert_arn" 2>/dev/null || true
}

@test "ACM: get certificate returns PEM format" {
    local domain_name="get-$(date +%s).${DOMAIN_SUFFIX}"

    # Create certificate first
    local create_output=$(aws acm request-certificate --domain-name "$domain_name")
    local cert_arn=$(echo "$create_output" | jq -r '.CertificateArn')

    # Wait briefly for emulator auto-validation
    sleep 1

    # Get certificate - may fail if still pending
    run aws acm get-certificate --certificate-arn "$cert_arn"

    if [ "$status" -eq 0 ]; then
        # Verify PEM format
        local cert_body=$(echo "$output" | jq -r '.Certificate')
        [[ "$cert_body" =~ ^-----BEGIN\ CERTIFICATE----- ]] || fail "Certificate not in PEM format"
    else
        # Skip if pending validation
        if [[ "$output" =~ "RequestInProgressException" ]] || [[ "$output" =~ "in progress" ]]; then
            skip "Certificate still pending validation"
        else
            fail "Unexpected error: $output"
        fi
    fi

    # Cleanup
    aws acm delete-certificate --certificate-arn "$cert_arn" 2>/dev/null || true
}

@test "ACM: delete certificate" {
    local domain_name="delete-$(date +%s).${DOMAIN_SUFFIX}"

    # Create certificate first
    local create_output=$(aws acm request-certificate --domain-name "$domain_name")
    local cert_arn=$(echo "$create_output" | jq -r '.CertificateArn')

    # Delete the certificate
    run aws acm delete-certificate --certificate-arn "$cert_arn"
    assert_success

    # Verify deletion - certificate should not be in list
    local list_output=$(aws acm list-certificates)
    run jq -e ".CertificateSummaryList[] | select(.CertificateArn == \"$cert_arn\")" <<< "$list_output"
    assert_failure  # Should fail because certificate is gone
}

@test "ACM: delete non-existent certificate fails" {
    local fake_arn="arn:aws:acm:us-east-1:123456789012:certificate/00000000-0000-0000-0000-000000000000"

    run aws acm delete-certificate --certificate-arn "$fake_arn"
    assert_failure
}
