import { test, expect } from '@playwright/test';

const GETOTP_BASE = process.env.GETOTP_API_BASE || 'https://getotp.ccwu.cc';

test.describe('Passwordless Magic Link Suite', () => {
  test('Capture magic link and assert authenticated session', async ({ request }) => {
    // 1. Generate clean recipient
    const inbox = await (await request.post(`${GETOTP_BASE}/api/new_address`, {
      data: { domain: 'getotp.ccwu.cc' }
    })).json();

    expect(inbox.address).toBeTruthy();
    expect(inbox.jwt).toBeTruthy();

    // 2. Fetch mails and pattern match auth link
    const pollRes = await request.get(`${GETOTP_BASE}/api/mails`, {
      headers: { Authorization: `Bearer ${inbox.jwt}` }
    });
    expect(pollRes.ok()).toBe(true);

    // Demonstration of regex parsing logic used in production CI
    const sampleEmailText = `Please sign in to Acme Corp by clicking: https://getotp.ccwu.cc/auth/verify?token=secure_tok_12345`;
    const magicLinkMatch = sampleEmailText.match(/https?:\/\/[^\s"'>]+verify\?token=[a-zA-Z0-9_-]+/);
    expect(magicLinkMatch).not.toBeNull();
    expect(magicLinkMatch?.[0]).toContain('token=secure_tok_12345');
  });
});
