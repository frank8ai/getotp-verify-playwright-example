# Changelog

All notable changes to this project will be documented in this file.

## [1.1.0] - 2026-10-04

### Added
- `src/getotp.ts`: Minimal TypeScript client helper transforming GetOTP Verify into an authentication-testing primitive for Playwright and CI runners (`createRun`, `waitForOTP`, `waitForMagicLink`, `finish`).
- Bounded HTTP polling with `Retry-After` support and default 30–60s timeouts (no unbounded loops, no WebSockets/SSE).
- Actionable typed errors (`mail_not_received`, `extract_no_match`, `ambiguous_match`, `run_limit_exceeded`, `quota_exceeded`, `live_storage_full`, `address_expired`, `storage_unavailable`, `auth_scope_denied`).
- Comprehensive unit test suite in `tests/client-helper.spec.ts` asserting exact error mappings and bounded polling behavior.
- Strict zero-log privacy guarantee ensuring no raw OTP codes or magic links appear in error messages or logs.
