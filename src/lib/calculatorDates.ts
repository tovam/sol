import { evaluateCalculatorExpression, isCalculatorExpressionCandidate } from "./unitExpression.ts";

export const DEFAULT_CALCULATOR_DATE_FORMAT = "YYYY-MM-DD";
const DATE_QUERY = /^(today|now|\d{4}-\d{2}-\d{2})(?:\s*([+-])\s*(.+))?$/i;

export function isDateCalculationCandidate(query: string) {
	const match = query.trim().match(DATE_QUERY);
	return !!match && (!match[2] || isCalculatorExpressionCandidate(match[3]));
}

export function formatCalculatorDate(date: Date, pattern: string) {
	const pad = (n: number) => String(n).padStart(2, "0");
	const tokens: Record<string, string> = {
		YYYY: String(date.getFullYear()), MM: pad(date.getMonth() + 1), DD: pad(date.getDate()),
		dddd: date.toLocaleDateString(undefined, { weekday: "long" }),
		ddd: date.toLocaleDateString(undefined, { weekday: "short" }),
	};
	return (pattern.trim() || DEFAULT_CALCULATOR_DATE_FORMAT).replace(/YYYY|MM|DD|dddd|ddd/g, (token) => tokens[token]);
}

export function evaluateDateCalculation(
	query: string,
	pattern = DEFAULT_CALCULATOR_DATE_FORMAT,
	now = new Date(),
	monthDays?: "30" | "30.4375",
) {
	const match = query.trim().match(DATE_QUERY);
	if (!match) return null;
	const anchor = match[1].toLowerCase();
	const isNow = anchor === "now";
	let date = new Date(now.getTime());
	if (!isNow) date.setHours(0, 0, 0, 0);
	if (anchor !== "today" && !isNow) {
		const [year, month, day] = anchor.split("-").map(Number);
		date.setFullYear(year, month - 1, day);
		if (date.getFullYear() !== year || date.getMonth() !== month - 1 || date.getDate() !== day) return null;
	}
	let interpretedExpression = anchor;
	let seconds = 0;
	if (match[2]) {
		const duration = evaluateCalculatorExpression(`(${match[3]}) in s`, null, monthDays);
		if (!duration) return null;
		seconds = Number(duration.value) * (match[2] === "-" ? -1 : 1);
		if (!Number.isFinite(seconds)) return null;
		interpretedExpression = `${anchor} ${match[2]} (${duration.interpretedExpression.replace(/ → s$/, "")})`;
		// Date-only anchors use calendar days; now uses elapsed time, including across DST.
		if (!isNow && Number.isInteger(seconds / 86400)) date.setDate(date.getDate() + seconds / 86400);
		else date = new Date(date.getTime() + seconds * 1000);
	}
	if (!Number.isFinite(date.getTime())) return null;
	const showTime = isNow || seconds % 86400 !== 0;
	const today = date.getFullYear() === now.getFullYear() && date.getMonth() === now.getMonth() && date.getDate() === now.getDate();
	const displayParts = [{ text: formatCalculatorDate(date, pattern), muted: showTime && today }];
	if (showTime) displayParts.push({ text: ` ${String(date.getHours()).padStart(2, "0")}:${String(date.getMinutes()).padStart(2, "0")}`, muted: false });
	const value = displayParts.map((part) => part.text).join("");
	return { kind: "calculation" as const, expression: query.trim(), interpretedExpression, value, copyValue: value, displayParts };
}
