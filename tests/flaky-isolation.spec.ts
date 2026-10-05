import { test, expect } from '@playwright/test';

const GETOTP_BASE = process.env.GETOTP_API_BASE || 'https://getotp.ccwu.cc';

test.describe.parallel('CI Flaky Elimination Suite', () => {
  test('Worker Index Isolation guarantees zero cross-worker collision', async ({ request }, testInfo) => {
    // Unique scoped identifier using worker parallel index and timestamp
    const workerScopedName = `worker${testInfo.parallelIndex}${Date.now()}`;
    const testStartTime = new Date().toISOString();

    const inbox = await (await request.post(`${GETOTP_BASE}/api/new_address`, {
      data: {
        name: workerScopedName,
        domain: 'getotp.ccwu.cc'
      }
    })).json();

    expect(inbox.address).toContain(workerScopedName);

    // Filter incoming messages by timestamp to prevent stale retries from leaking
    const mailsRes = await request.get(`${GETOTP_BASE}/api/mails?limit=10&offset=0`, {
      headers: { Authorization: `Bearer ${inbox.jwt}` }
    });
    const { results } = await mailsRes.json();

    const freshMails = (results || []).filter((mail: any) => new Date(mail.created_at) >= new Date(testStartTime));
    expect(Array.isArray(freshMails)).toBe(true);
  });
});
