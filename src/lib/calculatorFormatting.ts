import Big from "big.js";

const THIN_SPACE = "\u2009";

function groupDigits(value: string, size: number, fromRight: boolean) {
	if (value.length <= size) return value;
	if (fromRight) {
		const first = value.length % size || size;
		return [value.slice(0, first), ...(value.slice(first).match(new RegExp(`.{1,${size}}`, "g")) ?? [])].join(THIN_SPACE);
	}
	return value.match(new RegExp(`.{1,${size}}`, "g"))?.join(THIN_SPACE) ?? value;
}

export function groupDecimalForDisplay(input: string) {
	return input.replace(/^(-?)(\d+)(?:\.(\d+))?([eE][+-]?\d+)?/, (_match, sign, integer, fraction, exponent) =>
		`${sign}${groupDigits(integer, 3, true)}${fraction ? `.${groupDigits(fraction, 3, false)}` : ""}${exponent ?? ""}`,
	);
}

// Display only: calculations and clipboard values keep their original precision.
export function abbreviatedDecimal(value: string, decimals = 2): string {
	const exact = new Big(value);
	const truncated = exact.round(decimals, Big.roundDown);
	const isAbbreviated = !exact.eq(truncated);
	return `${exact.lt("0") && truncated.eq("0") ? "-" : ""}${truncated.toFixed(isAbbreviated ? decimals : undefined)}${isAbbreviated ? "..." : ""}`;
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
