# Factory v5 Pilot Integration & Verification Guide

This document outlines the standard verification process for integrating autonomous software factory runners with GetOTP Playwright test suites.

## 1. Scope and Objective

The purpose of this guide is to ensure that external coding agents execute non-destructive, reproducible tasks while strictly obeying the boundary contracts established in Factory v5.0.

## 2. Key Verification Rules

- **Isolated Runner**: Every runner must operate within a clean, sandboxed workspace without inheriting broad production tokens.
- **Strict Idempotency**: Pull requests dispatched by the factory broker must verify remote HEAD state to prevent duplicate submissions.
- **Manual Merge Boundary**: Until Phase 6 server-side branch protection and AER trust gates are formally verified, all pull requests generated in Phase 3 remain subject to manual human review and merge.

## 3. Maintenance Contact

Maintained by the Autonomous Software Factory core engineering team.
