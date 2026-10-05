/**
 * Minimal TypeScript helper for GetOTP Verify authentication-testing primitive.
 * Safe for Playwright, CI runners, and agent pipelines.
 *
 * Implements bounded HTTP polling, retry backoff, actionable typed errors,
 * and zero raw token/code credential exposure in error messages or logs.
 */

export type RunResult = 'pass' | 'fail';

export type CreateRunOptions = {
    lease_minutes?: number;
    address_ttl_hours?: number;
};

export type WaitOptions = {
    sender?: string;
    subject?: string;
    timeoutMs?: number;
    pollIntervalMs?: number;
};

export type VerificationRun = {
    run_id: string;
    email: string;
    lease_expires_at: string;
    address_expires_at: string;
};

export type OTPMatchResult = {
    status: 'matched';
    type: 'otp';
    value: string;
    message_id: string;
    received_at: string;
};

export type MagicLinkMatchResult = {
    status: 'matched';
    type: 'magic_link';
    url: string;
    message_id: string;
    received_at: string;
};

export type BackendMatchResponse =
    | OTPMatchResult
    | MagicLinkMatchResult
    | { status: 'pending' }
    | { status: 'extract_no_match' }
    | { status: 'ambiguous_match' }
    | { status: 'expired' };

export type VerifyErrorCode =
    | 'mail_not_received'
    | 'extract_no_match'
    | 'ambiguous_match'
    | 'run_limit_exceeded'
    | 'quota_exceeded'
    | 'live_storage_full'
    | 'address_expired'
    | 'storage_unavailable'
    | 'auth_scope_denied';

export class VerifyError extends Error {
    readonly code: VerifyErrorCode;
    readonly status?: number;

    constructor(code: VerifyErrorCode, message: string, status?: number) {
        super(message);
        this.name = 'VerifyError';
        this.code = code;
        this.status = status;
        Object.setPrototypeOf(this, VerifyError.prototype);
    }
}

export type GetOTPClientConfig = {
    baseUrl?: string;
    apiKey?: string;
};

export class VerificationRunSession {
    readonly run: VerificationRun;
    private readonly client: GetOTPClient;

    constructor(run: VerificationRun, client: GetOTPClient) {
        this.run = run;
        this.client = client;
    }

    get run_id(): string {
        return this.run.run_id;
    }

    get email(): string {
        return this.run.email;
    }

    async waitForOTP(options: WaitOptions = {}): Promise<OTPMatchResult> {
        return (await this.client.pollMatch(this.run.run_id, 'otp', options)) as OTPMatchResult;
    }

    async waitForMagicLink(options: WaitOptions = {}): Promise<MagicLinkMatchResult> {
        return (await this.client.pollMatch(this.run.run_id, 'magic_link', options)) as MagicLinkMatchResult;
    }

    async finish(result: RunResult): Promise<void> {
        await this.client.finishRun(this.run.run_id, result);
    }
}

export class GetOTPClient {
    readonly baseUrl: string;
    readonly apiKey: string;

    constructor(config: GetOTPClientConfig = {}) {
        this.baseUrl = (config.baseUrl || process.env.GETOTP_BASE || process.env.GETOTP_API_BASE || 'https://getotp.ccwu.cc').replace(/\/+$/, '');
        this.apiKey = config.apiKey || process.env.GETOTP_API_KEY || '';
    }

    private getHeaders(): Record<string, string> {
        const headers: Record<string, string> = {
            'Content-Type': 'application/json',
            'Accept': 'application/json',
        };
        if (this.apiKey) {
            headers['Authorization'] = `Bearer ${this.apiKey}`;
        }
        return headers;
    }

    private mapHttpStatusToError(status: number, errBody: any): VerifyError {
        const msg = errBody?.message || errBody?.error || `HTTP ${status}`;
        if (status === 401 || status === 403 || status === 404) {
            return new VerifyError('auth_scope_denied', 'Authentication failed or resource outside authorized scope', status);
        }
        if (status === 429) {
            if (/quota/i.test(msg)) {
                return new VerifyError('quota_exceeded', 'Monthly inbound email quota exceeded for account', status);
            }
            if (/storage|bytes|cap/i.test(msg)) {
                return new VerifyError('live_storage_full', 'Live raw byte storage cap exceeded for account', status);
            }
            return new VerifyError('run_limit_exceeded', 'Concurrency run limit reached for account plan', status);
        }
        if (status >= 500) {
            return new VerifyError('storage_unavailable', 'Storage backend or database temporarily unavailable', status);
        }
        return new VerifyError('storage_unavailable', `Request failed with status ${status}`, status);
    }

    async createRun(options: CreateRunOptions = {}): Promise<VerificationRunSession> {
        let res: Response;
        try {
            res = await fetch(`${this.baseUrl}/v1/runs`, {
                method: 'POST',
                headers: this.getHeaders(),
                body: JSON.stringify(options),
            });
        } catch (e) {
            throw new VerifyError('storage_unavailable', 'Failed to connect to GetOTP service');
        }

        if (!res.ok) {
            let body: any = {};
            try { body = await res.json(); } catch {}
            throw this.mapHttpStatusToError(res.status, body);
        }

        const runData = (await res.json()) as VerificationRun;
        return new VerificationRunSession(runData, this);
    }

    async finishRun(runId: string, result: RunResult): Promise<void> {
        let res: Response;
        try {
            res = await fetch(`${this.baseUrl}/v1/runs/${encodeURIComponent(runId)}/finish`, {
                method: 'POST',
                headers: this.getHeaders(),
                body: JSON.stringify({ result }),
            });
        } catch (e) {
            throw new VerifyError('storage_unavailable', 'Failed to connect to GetOTP service during finish');
        }

        if (!res.ok) {
            let body: any = {};
            try { body = await res.json(); } catch {}
            throw this.mapHttpStatusToError(res.status, body);
        }
    }

    async pollMatch(
        runId: string,
        type: 'otp' | 'magic_link',
        options: WaitOptions = {}
    ): Promise<OTPMatchResult | MagicLinkMatchResult> {
        const timeoutMs = typeof options.timeoutMs === 'number' && options.timeoutMs > 0 ? options.timeoutMs : 45000;
        const defaultPollInterval = 2000;
        const startTime = Date.now();

        const params = new URLSearchParams();
        params.set('type', type);
        if (options.sender) params.set('sender', options.sender);
        if (options.subject) params.set('subject', options.subject);
        const url = `${this.baseUrl}/v1/runs/${encodeURIComponent(runId)}/match?${params.toString()}`;

        while (true) {
            const elapsed = Date.now() - startTime;
            if (elapsed >= timeoutMs) {
                throw new VerifyError('mail_not_received', `Timeout (${Math.round(timeoutMs / 1000)}s) waiting for ${type} verification email`);
            }

            let res: Response;
            try {
                res = await fetch(url, {
                    method: 'GET',
                    headers: this.getHeaders(),
                });
            } catch (e) {
                throw new VerifyError('storage_unavailable', 'Network error connecting to GetOTP service');
            }

            if (!res.ok) {
                let errBody: any = {};
                try { errBody = await res.json(); } catch {}
                throw this.mapHttpStatusToError(res.status, errBody);
            }

            // Inspect Retry-After header if present
            let retryAfterMs = defaultPollInterval;
            const retryHeader = res.headers.get('Retry-After');
            if (retryHeader) {
                const parsed = parseInt(retryHeader, 10);
                if (!isNaN(parsed) && parsed > 0) {
                    retryAfterMs = parsed * 1000;
                }
            } else if (typeof options.pollIntervalMs === 'number' && options.pollIntervalMs > 0) {
                retryAfterMs = options.pollIntervalMs;
            }

            const data = (await res.json()) as BackendMatchResponse;

            if (data.status === 'matched') {
                return data;
            }

            if (data.status === 'extract_no_match') {
                throw new VerifyError('extract_no_match', 'Email received but no matching code or authentication link could be extracted');
            }

            if (data.status === 'ambiguous_match') {
                throw new VerifyError('ambiguous_match', 'Multiple conflicting verification codes or magic links detected; refine sender or subject filter');
            }

            if (data.status === 'expired') {
                throw new VerifyError('address_expired', 'Verification run lease or recipient address has expired');
            }

            // Pending: bounded sleep before next poll
            const remaining = timeoutMs - (Date.now() - startTime);
            if (remaining <= 0) {
                throw new VerifyError('mail_not_received', `Timeout (${Math.round(timeoutMs / 1000)}s) waiting for ${type} verification email`);
            }
            const sleepTime = Math.min(retryAfterMs, remaining);
            await new Promise((resolve) => setTimeout(resolve, sleepTime));
        }
    }
}

// Module-level default singleton helpers
let defaultClient: GetOTPClient | null = null;
const getDefaultClient = (): GetOTPClient => {
    if (!defaultClient) {
        defaultClient = new GetOTPClient();
    }
    return defaultClient;
};

export const createRun = (options?: CreateRunOptions): Promise<VerificationRunSession> => {
    return getDefaultClient().createRun(options);
};
