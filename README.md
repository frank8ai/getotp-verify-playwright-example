# GetOTP Verify — Playwright Email Testing Example

[![Playwright Tests](https://github.com/frank8ai/getotp-verify-playwright-example/actions/workflows/playwright.yml/badge.svg)](https://github.com/frank8ai/getotp-verify-playwright-example/actions)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

> Production-ready, zero-flaky email authentication testing suite for [Playwright](https://playwright.dev/) using **[GetOTP Verify](https://getotp.ccwu.cc/verify)**.

---

## ⚡ What is GetOTP Verify?
**GetOTP Verify** is an inbound email testing infrastructure designed for developers and CI/CD pipelines:
- **Instant Inboxes:** Create isolated, ephemeral inboxes in a single API call (`POST /api/new_address`).
- **Zero Flakiness:** Isolated test addresses prevent cross-worker message collision in parallel runs.
- **Auto OTP & Magic Link Extraction:** Pattern-match 4–8 digit verification codes and login tokens in real-time.
- **AI Agent Native:** Built-in support for autonomous agents, Webhooks, and machine-readable OpenAPI specs.

---

## 🚀 Quickstart (Run in 60 seconds)

### 1. Clone & Install
```bash
git clone https://github.com/frank8ai/getotp-verify-playwright-example.git
cd getotp-verify-playwright-example
npm install
npx playwright install chromium
```

### 2. Run Tests
```bash
npx playwright test
```

### 3. View Test Report
```bash
npx playwright show-report
```

---

## 📂 Included Test Scenarios

| Test File | Description | Target Flow |
| :--- | :--- | :--- |
| `tests/auth-otp.spec.ts` | Complete OTP flow | Sign up → Trigger email → Extract 6-digit code → Complete assertion |
| `tests/magic-link.spec.ts` | Passwordless login | Request magic link → Parse target token → Navigate & verify session |
| `tests/flaky-isolation.spec.ts` | Parallel CI suite | Scope mailbox by parallelIndex and filter messages by start timestamp |
| `tests/password-reset.spec.ts` | Password reset | Trigger reset → Extract token → Assert reset capability |

---

## 💻 Minimal Code Example

```typescript
import { test, expect } from '@playwright/test';

test('Verify registration with OTP code', async ({ page, request }) => {
  // 1. Create a clean ephemeral test address in 1 request
  const { address, jwt } = await (await request.post('https://getotp.ccwu.cc/api/new_address', {
    data: { domain: 'getotp.ccwu.cc' }
  })).json();

  // 2. Trigger your SaaS app signup
  await page.goto('https://yourapp.com/signup');
  await page.fill('#email', address);
  await page.click('#submit-btn');

  // 3. Poll GetOTP API for verification mail
  let otpCode = null;
  for (let i = 0; i < 15; i++) {
    await page.waitForTimeout(2000);
    const res = await (await request.get('https://getotp.ccwu.cc/api/mails?limit=1', {
      headers: { Authorization: `Bearer ${jwt}` }
    })).json();

    if (res.results?.length > 0) {
      const match = (res.results[0].text || res.results[0].subject).match(/\b\d{6}\b/);
      if (match) { otpCode = match[0]; break; }
    }
  }

  expect(otpCode).not.toBeNull();

  // 4. Fill code & complete assertion
  await page.fill('#otp-input', otpCode);
  await page.click('#verify-btn');
  await expect(page.locator('#dashboard')).toBeVisible();
});
```

---

## 💰 Pricing & Plans

| Plan | Monthly Fee | Included Inbound Emails | Parallel Mailboxes | Scope |
| :--- | :--- | :--- | :--- | :--- |
| **Free** | **$0** | **100 / mo** | 2 Workers | Free forever, no credit card required |
| **Developer** | **$19** | **10,000 / mo** | 10 Workers | Single project CI suite |
| **Team** | **$49** | **50,000 / mo** | 50 Workers | Up to 5 isolated projects, .COM domains |

- **Capacity Add-on:** `$10 / 10,000 emails`
- **Official Documentation:** [https://getotp.ccwu.cc/verify](https://getotp.ccwu.cc/verify)
- **Pricing Details:** [https://getotp.ccwu.cc/pricing](https://getotp.ccwu.cc/pricing)

---

## 📄 License
MIT © [GetOTP](https://getotp.ccwu.cc)
