import { test, expect } from "@playwright/test";
import { GetOTPClient, VerifyError, VerificationRunSession } from "../src/getotp";

test.describe("GetOTP Client Helper Unit Suite", () => {
    test("Successful OTP polling returns matched result", async () => {
        let callCount = 0;
        const fakeFetch = async (url: string, init?: RequestInit): Promise<Response> => {
            if (url.includes("/v1/runs/run_test/match")) {
                callCount++;
                if (callCount === 1) {
                    return new Response(JSON.stringify({ status: "pending" }), { status: 200, headers: { "Content-Type": "application/json" } });
                }
                return new Response(JSON.stringify({
                    status: "matched",
                    type: "otp",
                    value: "654321",
                    message_id: "msg_123",
                    received_at: "2026-10-04T12:00:00.000Z"
                }), { status: 200, headers: { "Content-Type": "application/json" } });
            }
            return new Response(JSON.stringify({ error: "not found" }), { status: 404 });
        };

        const originalFetch = global.fetch;
        global.fetch = fakeFetch as any;
        try {
            const client = new GetOTPClient({ baseUrl: "https://test.getotp.ccwu.cc", apiKey: "test_key" });
            const session = new VerificationRunSession({
                run_id: "run_test",
                email: "run_test@getotp.ccwu.cc",
                lease_expires_at: "2026-10-04T12:10:00Z",
                address_expires_at: "2026-10-04T13:00:00Z",
            }, client);

            const otp = await session.waitForOTP({ timeoutMs: 5000, pollIntervalMs: 50 });
            expect(otp.status).toBe("matched");
            expect(otp.type).toBe("otp");
            expect(otp.value).toBe("654321");
            expect(otp.message_id).toBe("msg_123");
            expect(callCount).toBe(2);
        } finally {
            global.fetch = originalFetch;
        }
    });

    test("Successful Magic Link polling returns matched result", async () => {
        const fakeFetch = async (url: string): Promise<Response> => {
            if (url.includes("type=magic_link")) {
                return new Response(JSON.stringify({
                    status: "matched",
                    type: "magic_link",
                    url: "https://example.com/auth/verify?token=secure123",
                    message_id: "msg_link_456",
                    received_at: "2026-10-04T12:00:00.000Z"
                }), { status: 200, headers: { "Content-Type": "application/json" } });
            }
            return new Response(JSON.stringify({ status: "pending" }), { status: 200 });
        };

        const originalFetch = global.fetch;
        global.fetch = fakeFetch as any;
        try {
            const client = new GetOTPClient({ baseUrl: "https://test.getotp.ccwu.cc" });
            const session = new VerificationRunSession({
                run_id: "run_ml",
                email: "run_ml@getotp.ccwu.cc",
                lease_expires_at: "2026-10-04T12:10:00Z",
                address_expires_at: "2026-10-04T13:00:00Z",
            }, client);

            const ml = await session.waitForMagicLink({ timeoutMs: 5000, pollIntervalMs: 50 });
            expect(ml.status).toBe("matched");
            expect(ml.type).toBe("magic_link");
            expect(ml.url).toBe("https://example.com/auth/verify?token=secure123");
            expect(ml.message_id).toBe("msg_link_456");
        } finally {
            global.fetch = originalFetch;
        }
    });

    test("Timeout maps strictly to mail_not_received error", async () => {
        const fakeFetch = async (): Promise<Response> => {
            return new Response(JSON.stringify({ status: "pending" }), { status: 200, headers: { "Content-Type": "application/json" } });
        };

        const originalFetch = global.fetch;
        global.fetch = fakeFetch as any;
        try {
            const client = new GetOTPClient({ baseUrl: "https://test.getotp.ccwu.cc" });
            const session = new VerificationRunSession({
                run_id: "run_timeout",
                email: "run_timeout@getotp.ccwu.cc",
                lease_expires_at: "2026-10-04T12:10:00Z",
                address_expires_at: "2026-10-04T13:00:00Z",
            }, client);

            await expect(session.waitForOTP({ timeoutMs: 150, pollIntervalMs: 50 }))
                .rejects.toThrow("Timeout");
            try {
                await session.waitForOTP({ timeoutMs: 150, pollIntervalMs: 50 });
            } catch (err: any) {
                expect(err).toBeInstanceOf(VerifyError);
                expect(err.code).toBe("mail_not_received");
            }
        } finally {
            global.fetch = originalFetch;
        }
    });

    test("Backend extract_no_match maps to typed error", async () => {
        const fakeFetch = async (): Promise<Response> => {
            return new Response(JSON.stringify({ status: "extract_no_match" }), { status: 200, headers: { "Content-Type": "application/json" } });
        };

        const originalFetch = global.fetch;
        global.fetch = fakeFetch as any;
        try {
            const client = new GetOTPClient({ baseUrl: "https://test.getotp.ccwu.cc" });
            const session = new VerificationRunSession({
                run_id: "run_nomatch",
                email: "run_nomatch@getotp.ccwu.cc",
                lease_expires_at: "2026-10-04T12:10:00Z",
                address_expires_at: "2026-10-04T13:00:00Z",
            }, client);

            try {
                await session.waitForOTP({ timeoutMs: 1000, pollIntervalMs: 50 });
                expect(true).toBe(false);
            } catch (err: any) {
                expect(err).toBeInstanceOf(VerifyError);
                expect(err.code).toBe("extract_no_match");
            }
        } finally {
            global.fetch = originalFetch;
        }
    });

    test("Backend ambiguous_match maps to typed error", async () => {
        const fakeFetch = async (): Promise<Response> => {
            return new Response(JSON.stringify({ status: "ambiguous_match" }), { status: 200, headers: { "Content-Type": "application/json" } });
        };

        const originalFetch = global.fetch;
        global.fetch = fakeFetch as any;
        try {
            const client = new GetOTPClient({ baseUrl: "https://test.getotp.ccwu.cc" });
            const session = new VerificationRunSession({
                run_id: "run_ambiguous",
                email: "run_ambiguous@getotp.ccwu.cc",
                lease_expires_at: "2026-10-04T12:10:00Z",
                address_expires_at: "2026-10-04T13:00:00Z",
            }, client);

            try {
                await session.waitForOTP({ timeoutMs: 1000, pollIntervalMs: 50 });
                expect(true).toBe(false);
            } catch (err: any) {
                expect(err).toBeInstanceOf(VerifyError);
                expect(err.code).toBe("ambiguous_match");
            }
        } finally {
            global.fetch = originalFetch;
        }
    });

    test("Backend expired status maps to address_expired error", async () => {
        const fakeFetch = async (): Promise<Response> => {
            return new Response(JSON.stringify({ status: "expired" }), { status: 200, headers: { "Content-Type": "application/json" } });
        };

        const originalFetch = global.fetch;
        global.fetch = fakeFetch as any;
        try {
            const client = new GetOTPClient({ baseUrl: "https://test.getotp.ccwu.cc" });
            const session = new VerificationRunSession({
                run_id: "run_exp",
                email: "run_exp@getotp.ccwu.cc",
                lease_expires_at: "2026-10-04T12:10:00Z",
                address_expires_at: "2026-10-04T13:00:00Z",
            }, client);

            try {
                await session.waitForOTP({ timeoutMs: 1000, pollIntervalMs: 50 });
                expect(true).toBe(false);
            } catch (err: any) {
                expect(err).toBeInstanceOf(VerifyError);
                expect(err.code).toBe("address_expired");
            }
        } finally {
            global.fetch = originalFetch;
        }
    });

    test("HTTP 429 quota error maps to quota_exceeded", async () => {
        const fakeFetch = async (): Promise<Response> => {
            return new Response(JSON.stringify({ error: "Monthly quota exceeded" }), { status: 429, headers: { "Content-Type": "application/json" } });
        };

        const originalFetch = global.fetch;
        global.fetch = fakeFetch as any;
        try {
            const client = new GetOTPClient({ baseUrl: "https://test.getotp.ccwu.cc" });
            try {
                await client.createRun();
                expect(true).toBe(false);
            } catch (err: any) {
                expect(err).toBeInstanceOf(VerifyError);
                expect(err.code).toBe("quota_exceeded");
                expect(err.status).toBe(429);
            }
        } finally {
            global.fetch = originalFetch;
        }
    });

    test("HTTP 401 error maps to auth_scope_denied", async () => {
        const fakeFetch = async (): Promise<Response> => {
            return new Response(JSON.stringify({ error: "Unauthorized" }), { status: 401, headers: { "Content-Type": "application/json" } });
        };

        const originalFetch = global.fetch;
        global.fetch = fakeFetch as any;
        try {
            const client = new GetOTPClient({ baseUrl: "https://test.getotp.ccwu.cc" });
            try {
                await client.createRun();
                expect(true).toBe(false);
            } catch (err: any) {
                expect(err).toBeInstanceOf(VerifyError);
                expect(err.code).toBe("auth_scope_denied");
                expect(err.status).toBe(401);
            }
        } finally {
            global.fetch = originalFetch;
        }
    });

    test("finish('pass') executes finish endpoint without error", async () => {
        let finishCalled = false;
        const fakeFetch = async (url: string, init?: RequestInit): Promise<Response> => {
            if (url.includes("/v1/runs/run_pass_test/finish")) {
                finishCalled = true;
                const body = JSON.parse(init?.body as string);
                expect(body.result).toBe("pass");
                return new Response(JSON.stringify({ status: "pass" }), { status: 200 });
            }
            return new Response(JSON.stringify({ error: "not found" }), { status: 404 });
        };

        const originalFetch = global.fetch;
        global.fetch = fakeFetch as any;
        try {
            const client = new GetOTPClient({ baseUrl: "https://test.getotp.ccwu.cc" });
            const session = new VerificationRunSession({
                run_id: "run_pass_test",
                email: "run_pass_test@getotp.ccwu.cc",
                lease_expires_at: "2026-10-04T12:10:00Z",
                address_expires_at: "2026-10-04T13:00:00Z",
            }, client);

            await session.finish("pass");
            expect(finishCalled).toBe(true);
        } finally {
            global.fetch = originalFetch;
        }
    });
});
