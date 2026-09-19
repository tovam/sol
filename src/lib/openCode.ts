import axios from "axios";

export const DEFAULT_OPENCODE_URL = "http://opencode.localhost:55472/v1/mini-sessions";

export function resolveOpenCodePrompt(query: string): string | null {
	const match = query.match(/^\s*oc(?:\s+([\s\S]*))?$/i);
	return match ? (match[1] ?? "").trim() : null;
}

export async function openCodeMiniSession(endpoint: string, prompt: string) {
	if (!/^https?:\/\/[^\s/?#]+(?:[/?#][^\s]*)?$/i.test(endpoint.trim())) {
		throw new Error("Configure a valid OpenCode HTTP URL in General settings.");
	}
	const bytes = encodeURIComponent(prompt).replace(/%[0-9A-F]{2}/g, "x").length;
	if (bytes > 32 * 1024) throw new Error("OpenCode prompts are limited to 32 KiB.");
	await axios.post(endpoint.trim(), prompt ? { prompt } : {}, {
		headers: { "Content-Type": "application/json" },
		timeout: 10000,
	});
}
