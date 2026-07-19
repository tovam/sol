export type AIHTTPProvider = "openai" | "openwebui";

function trimTrailingSlashes(value: string) {
	return value.trim().replace(/\/+$/, "");
}

export function openAIEndpoint(baseURL: string) {
	const base = trimTrailingSlashes(baseURL);
	if (base.endsWith("/responses")) return base;
	if (base.endsWith("/v1")) return `${base}/responses`;
	return `${base}/v1/responses`;
}

export function openWebUIEndpoint(baseURL: string) {
	const base = trimTrailingSlashes(baseURL);
	if (base.endsWith("/api/chat/completions")) return base;
	if (base.endsWith("/api")) return `${base}/chat/completions`;
	return `${base}/api/chat/completions`;
}

export function createAIHeaders(
	provider: AIHTTPProvider,
	apiKey: string,
): Record<string, string> {
	const headers: Record<string, string> = {
		"Content-Type": "application/json",
	};
	const normalizedKey = apiKey.trim().replace(/^Bearer\s+/i, "");
	if (!normalizedKey) return headers;

	headers.Authorization = `Bearer ${normalizedKey}`;
	if (provider === "openwebui") {
		// OpenWebUI's default custom key header survives reverse proxies that
		// consume Authorization before forwarding the request.
		headers["x-api-key"] = normalizedKey;
	}
	return headers;
}
