import Big from "big.js";

// Display only: calculations and clipboard values keep their original precision.
export function abbreviatedDecimal(value: string, decimals = 2): string {
	const exact = new Big(value);
	const truncated = exact.round(decimals, Big.roundDown);
	return `${exact.lt("0") && truncated.eq("0") ? "-" : ""}${truncated.toFixed()}${exact.eq(truncated) ? "" : "..."}`;
}

const RATE_DECIMALS: Record<string, number> = { "EUR/USD": 2 };
export function abbreviatedExchangeRate(value: string, source: string, target: string) {
	return abbreviatedDecimal(value, RATE_DECIMALS[[source, target].sort().join("/")] ?? 2);
}

export function formatRateAge(timestamp: number, now = Date.now()): string {
	const minutes = Math.max(0, Math.floor((now - timestamp) / 60000));
	if (!Number.isFinite(minutes)) return "unknown age";
	if (minutes < 1) return "just now";
	const [amount, unit] = minutes < 60 ? [minutes, "minute"]
		: minutes < 1440 ? [Math.floor(minutes / 60), "hour"]
		: [Math.floor(minutes / 1440), "day"];
	return `${amount} ${unit}${amount === 1 ? "" : "s"} ago`;
}
