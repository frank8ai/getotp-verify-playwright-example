# GetOTP Verify — Playwright Email Testing Example

[![Playwright Tests](https://github.com/frank8ai/getotp-verify-playwright-example/actions/workflows/playwright.yml/badge.svg)](https://github.com/frank8ai/getotp-verify-playwright-example/actions)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

> Automated email authentication testing suite for [Playwright](https://playwright.dev/) using **[GetOTP Verify](https://getotp.ccwu.cc/verify)**.

---

## ⚡ What is GetOTP Verify?
**GetOTP Verify** is an inbound email testing infrastructure designed for developers and CI/CD pipelines:
- **Instant Inboxes:** Create isolated, ephemeral inboxes in a single API call (`POST /api/new_address`).
- **Auto OTP & Magic Link Extraction:** Pattern-match 4–8 digit verification codes and login tokens in real-time.
- **Authentication-Testing Primitive:** Bounded HTTP polling helper with scoped candidate matching, disambiguation, and typed actionable errors.

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

## 🛡️ Authentication Testing Primitive Helper

A minimal TypeScript helper (`src/getotp.ts`) is included to eliminate boilerplate, handle bounded polling with `Retry-After`, and map backend matching outcomes directly into actionable typed errors without exposing credentials in logs.

```typescript
import { test, expect } from '@playwright/test';
import { createRun } from './src/getotp';

test('End-to-end OTP test with GetOTP Client Helper', async ({ page }) => {
  // 1. Create a scoped verification run (leases isolated ephemeral address)
  const session = await createRun();

  // 2. Trigger application email delivery
  await page.goto('https://yourapp.com/signup');
  await page.fill('#email', session.email);
  await page.click('#submit-btn');

  // 3. Wait for OTP with bounded polling (~2s interval, backoff, 45s default timeout)
  //    Supports optional sender and subject disambiguation filters
  const match = await session.waitForOTP({ sender: 'auth@yourapp.com' });
  
  // 4. Fill extracted code and verify
  await page.fill('#otp-input', match.value);
  await page.click('#verify-btn');
  await expect(page.locator('#dashboard')).toBeVisible();

  // 5. Finish run: immediately cleans up sensitive raw MIME content on pass
  await session.finish('pass');
});
```

### Typed Errors
When email polling fails or limits are reached, the helper throws a typed `VerifyError` with one of the following codes:
`mail_not_received`, `extract_no_match`, `ambiguous_match`, `run_limit_exceeded`, `quota_exceeded`, `live_storage_full`, `address_expired`, `storage_unavailable`, `auth_scope_denied`.

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

| Plan | Monthly Fee | Account Inbound Emails | Concurrent Test Runs | Ephemeral Addresses | Retention (Raw MIME) |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **Free** | **$0** | **100 / mo across account** | **2 concurrent runs** | Unique per run (auto-cleaned) | Max 24h (purge on pass) |
| **Developer** | **$19** | **10,000 / mo across account** | **10 concurrent runs** | Unique per run (auto-cleaned) | 24h retention |
| **Team** | **$49** | **50,000 / mo across account** | **50 concurrent runs** | Unique per run (auto-cleaned) | 24h retention |

- **Account-wide Quota:** Limits apply to total received & stored messages across all test addresses and namespaces.
- **Capacity Add-on:** `$10 / 10,000 emails`
- **Official Documentation:** [https://getotp.ccwu.cc/verify](https://getotp.ccwu.cc/verify)
- **Pricing Details:** [https://getotp.ccwu.cc/pricing](https://getotp.ccwu.cc/pricing)

- **Capacity Add-on:** `$10 / 10,000 emails`
- **Official Documentation:** [https://getotp.ccwu.cc/verify](https://getotp.ccwu.cc/verify)
- **Pricing Details:** [https://getotp.ccwu.cc/pricing](https://getotp.ccwu.cc/pricing)

---

## 📄 License
MIT © [GetOTP](https://getotp.ccwu.cc)
