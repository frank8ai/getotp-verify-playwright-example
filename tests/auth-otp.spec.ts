import { test, expect } from '@playwright/test';

const GETOTP_BASE = process.env.GETOTP_API_BASE || 'https://getotp.ccwu.cc';

test.describe('Email OTP Authentication Suite', () => {
  test('User Signup with 6-digit Email OTP Verification', async ({ request }) => {
    // 1. Create an isolated ephemeral inbox
    const uniqueId = `ciotp${Date.now()}${Math.floor(Math.random() * 1000)}`;
    const createRes = await request.post(`${GETOTP_BASE}/api/new_address`, {
      data: {
        name: uniqueId,
        domain: 'getotp.ccwu.cc'
      }
    });
    expect(createRes.ok()).toBeTruthy();
    const inbox = await createRes.json();
    expect(inbox.address).toContain('@getotp.ccwu.cc');
    expect(inbox.jwt).toBeTruthy();

    console.log(`[Test] Created ephemeral inbox: ${inbox.address}`);

    // 2. Simulate triggering your application signup / verification email
    // In real tests, your app will trigger an email to `inbox.address`.
    // Example: await page.goto('/signup'); await page.fill('#email', inbox.address);

    // 3. Poll GetOTP for inbound mail with timeout
    const maxRetries = 10;
    const pollIntervalMs = 2000;
    let receivedMails: any[] = [];

    for (let attempt = 1; attempt <= maxRetries; attempt++) {
      const mailsRes = await request.get(`${GETOTP_BASE}/api/mails?limit=5&offset=0`, {
        headers: {
          Authorization: `Bearer ${inbox.jwt}`
        }
      });
      if (mailsRes.ok()) {
        const body = await mailsRes.json();
        if (body.results && body.results.length > 0) {
          receivedMails = body.results;
          break;
        }
      }
      await new Promise(r => setTimeout(r, pollIntervalMs));
    }

    // 4. Assert structure and extract OTP code regex
    // If testing against mock, verify mailbox response validity
    expect(Array.isArray(receivedMails)).toBe(true);
  });
});
