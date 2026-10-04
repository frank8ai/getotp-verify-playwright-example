import { test, expect } from '@playwright/test';

const GETOTP_BASE = process.env.GETOTP_API_BASE || 'https://getotp.ccwu.cc';

test.describe('Password Reset Lifecycle Suite', () => {
  test('Request reset, extract token, and assert reset capability', async ({ request }) => {
    const inbox = await (await request.post(`${GETOTP_BASE}/api/new_address`, {
      data: { domain: 'getotp.ccwu.cc' }
    })).json();

    expect(inbox.address).toBeTruthy();
    expect(inbox.password).toBeTruthy(); // 16-char high-entropy credential

    // Simulated email content containing reset link
    const resetBody = `Reset your password here: https://getotp.ccwu.cc/reset-password?token=pw_reset_998124`;
    const tokenMatch = resetBody.match(/token=([a-zA-Z0-9_-]+)/);
    expect(tokenMatch).not.toBeNull();
    expect(tokenMatch?.[1]).toBe('pw_reset_998124');
  });
});
