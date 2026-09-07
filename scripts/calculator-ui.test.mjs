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
