const PUBLIC_IP_ENDPOINT = "https://api64.ipify.org?format=json";
const REQUEST_TIMEOUT_MS = 5_000;

function isIPv4(value: string): boolean {
	const parts = value.split(".");
	return (
		parts.length === 4 &&
		parts.every((part) => {
			if (!/^\d{1,3}$/.test(part)) return false;
			const octet = Number(part);
			return octet >= 0 && octet <= 255 && String(octet) === part;
		})
	);
}

function isIPv6(value: string): boolean {
	if (value.length > 45 || !value.includes(":")) return false;
	if (value.startsWith(":") && !value.startsWith("::")) return false;
	if (value.endsWith(":") && !value.endsWith("::")) return false;
	if (value.indexOf("::") !== value.lastIndexOf("::")) return false;

	const segments = value.split(":");
	const ipv4Tail = segments.at(-1)?.includes(".") ? segments.pop() : undefined;
	if (ipv4Tail != null && !isIPv4(ipv4Tail)) return false;

	const hextets = segments.filter(Boolean);
	if (!hextets.every((part) => /^[0-9a-f]{1,4}$/i.test(part))) return false;

	const expectedHextets = ipv4Tail == null ? 8 : 6;
	return value.includes("::")
		? hextets.length < expectedHextets
		: hextets.length === expectedHextets;
}

export function parsePublicIPAddress(payload: unknown): string | null {
	if (payload == null || typeof payload !== "object" || !("ip" in payload)) {
		return null;
	}

	const ip = (payload as { ip?: unknown }).ip;
	if (typeof ip !== "string") return null;

	const normalized = ip.trim();
	return isIPv4(normalized) || isIPv6(normalized) ? normalized : null;
}

export async function fetchPublicIPAddress(): Promise<string> {
	const controller = new AbortController();
	const timeout = setTimeout(() => controller.abort(), REQUEST_TIMEOUT_MS);

	try {
		const response = await fetch(PUBLIC_IP_ENDPOINT, {
			headers: { Accept: "application/json" },
			signal: controller.signal,
		});
		if (!response.ok) {
			throw new Error(`Public IP request failed (${response.status})`);
		}

		const ip = parsePublicIPAddress(await response.json());
		if (ip == null) {
			throw new Error("Public IP service returned an invalid response");
		}
		return ip;
	} finally {
		clearTimeout(timeout);
	}
}
