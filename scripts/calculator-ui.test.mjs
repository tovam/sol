import assert from "node:assert/strict";
import { registerHooks } from "node:module";
import test from "node:test";

// Resolve only the calculator's source aliases; never load the app or its data.
registerHooks({ resolve(specifier, context, nextResolve) {
	if (["lib/currencyRates", "lib/calculatorDates", "lib/unitExpression"].includes(specifier)) {
		return nextResolve(new URL(`../src/${specifier}.ts`, import.meta.url).href, context);
	}
	return nextResolve(specifier, context);
} });
const { parseCalculation, isCalculationCandidate } = await import("../src/stores/ui.store.helpers.ts");

test("month settings gate recognition and attach both result conventions", () => {
	const rates = { base: "EUR", rates: { EUR: "1", USD: "2", BTC: "0.0001" }, source: "Coinbase", fetchedAt: 1700000000000 };
	const money = parseCalculation("12.3456 USD/h in USD/h", rates);
	assert.equal(money.value, "12.34... USD/h");
	assert.equal(money.copyValue, "12.3456 USD/h");
	assert.deepEqual(money.displayParts[1], { text: "...", subtle: true });
	const hexadecimal = parseCalculation("0x10m + 1m");
	assert.equal(hexadecimal.value, "17 m · 0x11 m");
	assert.deepEqual(hexadecimal.displayParts.at(-1), { text: " · 0x11 m", muted: true });
	const variables = { zzz: "2384 m/s", delay: "1month", interval: "8j" };
	assert.equal(parseCalculation("zzz in m/s", null, undefined, false, variables).value, "2384 m/s");
	assert.equal(parseCalculation("delay in d", null, undefined, false, variables), null);
	assert.match(parseCalculation("delay in d", null, undefined, true, variables).monthAlternative, /30\.4375 d/);
	assert.equal(parseCalculation("2026-09-07 + interval", null, undefined, false, variables).value, "2026-09-15");
	assert.equal(isCalculationCandidate("1month in d"), false);
	assert.equal(isCalculationCandidate("1month in d", true), true);
	assert.equal(parseCalculation("1month in d"), null);
	const result = parseCalculation("1month in d", null, undefined, true);
	assert.equal(result.value, "30 d");
	assert.match(result.monthWarning, /30 j/);
	assert.match(result.monthAlternative, /30\.4375 d/);
	assert.equal(parseCalculation("1j in h", null, undefined, true).monthWarning, undefined);
	assert.match(parseCalculation("60d in month", null, undefined, true).monthAlternative, /1\.971/);
	assert.match(parseCalculation("2026-01-01 + 1month", null, undefined, true).monthAlternative, /2026-01-31 10:30/);
	assert.match(parseCalculation("1month in hmin", null, undefined, true).monthAlternative, /30j 10h 30min/);
});
