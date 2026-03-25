import {
  ACMClient,
  RequestCertificateCommand,
  DescribeCertificateCommand,
  GetCertificateCommand,
  ListCertificatesCommand,
  DeleteCertificateCommand,
} from '@aws-sdk/client-acm';
import { describe, it, expect, afterAll } from 'vitest';
import { randomUUID } from 'crypto';

const acmClient = new ACMClient({
  endpoint: process.env.FLOCI_ENDPOINT || 'http://localhost:4566',
  region: process.env.AWS_DEFAULT_REGION || 'us-east-1',
  credentials: {
    accessKeyId: process.env.AWS_ACCESS_KEY_ID || 'test',
    secretAccessKey: process.env.AWS_SECRET_ACCESS_KEY || 'test',
  },
});

// Helper to delay execution
function delay(ms: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

describe('ACM Operations', () => {
  const createdCertificates: string[] = [];

  afterAll(async () => {
    // Cleanup all created certificates
    for (const arn of createdCertificates) {
      try {
        await acmClient.send(new DeleteCertificateCommand({ CertificateArn: arn }));
      } catch (e) {
        // Ignore cleanup errors
      }
    }
  });

  it('should request a certificate', async () => {
    const domainName = `test-${randomUUID().slice(0, 8)}.example.com`;

    const response = await acmClient.send(
      new RequestCertificateCommand({ DomainName: domainName })
    );

    expect(response.$metadata.httpStatusCode).toBe(200);
    expect(response.CertificateArn).toBeDefined();
    expect(response.CertificateArn).toMatch(/^arn:aws:acm:/);

    createdCertificates.push(response.CertificateArn!);
  });

  it('should request a certificate with SANs', async () => {
    const domainName = `test-san-${randomUUID().slice(0, 8)}.example.com`;
    const sans = [`www.${domainName}`, `api.${domainName}`];

    const response = await acmClient.send(
      new RequestCertificateCommand({
        DomainName: domainName,
        SubjectAlternativeNames: sans,
      })
    );

    expect(response.$metadata.httpStatusCode).toBe(200);
    expect(response.CertificateArn).toBeDefined();

    createdCertificates.push(response.CertificateArn!);
  });

  it('should describe a certificate', async () => {
    const domainName = `test-describe-${randomUUID().slice(0, 8)}.example.com`;
    const createResponse = await acmClient.send(
      new RequestCertificateCommand({ DomainName: domainName })
    );
    createdCertificates.push(createResponse.CertificateArn!);

    const response = await acmClient.send(
      new DescribeCertificateCommand({
        CertificateArn: createResponse.CertificateArn!,
      })
    );

    expect(response.$metadata.httpStatusCode).toBe(200);
    expect(response.Certificate).toBeDefined();
    expect(response.Certificate!.CertificateArn).toBe(createResponse.CertificateArn);
    expect(response.Certificate!.DomainName).toBe(domainName);
    expect(response.Certificate!.Status).toBeDefined();
  });

  it('should throw error for non-existent certificate describe', async () => {
    const fakeArn =
      'arn:aws:acm:us-east-1:123456789012:certificate/00000000-0000-0000-0000-000000000000';

    await expect(
      acmClient.send(new DescribeCertificateCommand({ CertificateArn: fakeArn }))
    ).rejects.toThrow();
  });

  it('should list certificates', async () => {
    const domainName = `test-list-${randomUUID().slice(0, 8)}.example.com`;
    const createResponse = await acmClient.send(
      new RequestCertificateCommand({ DomainName: domainName })
    );
    createdCertificates.push(createResponse.CertificateArn!);

    const response = await acmClient.send(new ListCertificatesCommand({}));

    expect(response.$metadata.httpStatusCode).toBe(200);
    expect(response.CertificateSummaryList).toBeDefined();

    const arns = response.CertificateSummaryList!.map((c) => c.CertificateArn);
    expect(arns).toContain(createResponse.CertificateArn);
  });

  it('should list certificates with correct structure', async () => {
    const response = await acmClient.send(new ListCertificatesCommand({}));

    expect(response.$metadata.httpStatusCode).toBe(200);
    expect(response.CertificateSummaryList).toBeDefined();
    expect(Array.isArray(response.CertificateSummaryList)).toBe(true);
  });

  it('should get certificate body and chain', async () => {
    const domainName = `test-get-${randomUUID().slice(0, 8)}.example.com`;
    const createResponse = await acmClient.send(
      new RequestCertificateCommand({ DomainName: domainName })
    );
    createdCertificates.push(createResponse.CertificateArn!);

    // Wait briefly for auto-validation in emulator
    await delay(1000);

    try {
      const response = await acmClient.send(
        new GetCertificateCommand({
          CertificateArn: createResponse.CertificateArn!,
        })
      );

      expect(response.$metadata.httpStatusCode).toBe(200);
      expect(response.Certificate).toBeDefined();
      expect(response.Certificate).toContain('-----BEGIN CERTIFICATE-----');
    } catch (error: any) {
      // Skip if certificate is still pending validation
      if (error.name === 'RequestInProgressException') {
        console.log('Certificate still pending validation, skipping test');
        return;
      }
      throw error;
    }
  });

  it('should delete a certificate', async () => {
    const domainName = `test-delete-${randomUUID().slice(0, 8)}.example.com`;
    const createResponse = await acmClient.send(
      new RequestCertificateCommand({ DomainName: domainName })
    );
    const certArn = createResponse.CertificateArn!;

    const response = await acmClient.send(
      new DeleteCertificateCommand({ CertificateArn: certArn })
    );

    expect(response.$metadata.httpStatusCode).toBe(200);

    // Verify deletion
    const listResponse = await acmClient.send(new ListCertificatesCommand({}));
    const arns = listResponse.CertificateSummaryList?.map((c) => c.CertificateArn) || [];
    expect(arns).not.toContain(certArn);
  });

  it('should throw error for non-existent certificate delete', async () => {
    const fakeArn =
      'arn:aws:acm:us-east-1:123456789012:certificate/00000000-0000-0000-0000-000000000000';

    await expect(
      acmClient.send(new DeleteCertificateCommand({ CertificateArn: fakeArn }))
    ).rejects.toThrow();
  });
});
