import assert from "node:assert/strict";
import test from "node:test";
import {
	calculatorExpressionUsesCurrency,
	expandCalculatorVariables,
	validateCalculatorVariableName,
	evaluateCalculatorExpression,
	isCalculatorExpressionCandidate,
} from "../src/lib/unitExpression.ts";
import { parseCoinbaseCurrencyRates } from "../src/lib/currencyRates.ts";
import { evaluateDateCalculation, isDateCalculationCandidate } from "../src/lib/calculatorDates.ts";

test("calculates local dates using the unit engine", () => {
	const now = new Date(2026, 8, 7, 12, 30);
	const calculate = (q, format) => evaluateDateCalculation(q, format, now);
	assert.equal(calculate("today + 8j").value, "2026-09-15");
	assert.equal(calculate("now + (824km/130km/h)").value, "2026-09-07 18:50");
	assert.equal(calculate("now + (824km/130km/h)").displayParts[0].muted, true);
	assert.equal(calculate("now + 1j").displayParts[0].muted, false);
	assert.equal(calculate("today - 1w").value, "2026-08-31");
	assert.equal(calculate("2026-12-31 + 1j").value, "2027-01-01");
	assert.equal(calculate("2026-02-30 + 1j"), null);
	assert.equal(calculate("today + 1kg"), null);
	assert.equal(calculate("today", "DD/MM/YYYY").value, "07/09/2026");
	assert.equal(calculate("today", "dddd YYYY-MM-DD").value, `${now.toLocaleDateString(undefined, { weekday: "long" })} 2026-09-07`);
	assert.equal(isDateCalculationCandidate("today + 8j"), true);
	assert.equal(isDateCalculationCandidate("now + ("), false);
});

const currencyRates = {
	base: "EUR",
	rates: { EUR: "1", USD: "2", BTC: "0.0001" },
	fetchedAt: 1_700_000_000_000,
	source: "Coinbase",
};

function evaluate(expression) {
	const result = evaluateCalculatorExpression(expression);
	assert.ok(result, `Expected a result for: ${expression}`);
	return result;
}

function evaluateCurrency(expression) {
	const result = evaluateCalculatorExpression(expression, currencyRates);
	assert.ok(result, `Expected a currency result for: ${expression}`);
	return result;
}

test("inverts the entire expression with a leading or trailing inv", () => {
	for (const query of ["inv 2w in Hz", "2w inv in Hz", "INV 2w TO Hz"]) {
		assert.equal(isCalculatorExpressionCandidate(query), true);
		assert.deepEqual(evaluate(query), evaluate("1/(2w) in Hz"));
	}
	assert.deepEqual(evaluate("inv 2+3 in %"), evaluate("1/(2+3) in %"));
	assert.equal(evaluateCalculatorExpression("inv 2w in m"), null);
	assert.equal(evaluateCalculatorExpression("inv 0s in Hz"), null);
	for (const expression of ["inv 2+3", "2+3 inv", " INV 2+3 "]) {
		assert.equal(isCalculatorExpressionCandidate(expression), true);
		assert.equal(evaluate(expression).value, "0.2");
		assert.equal(evaluate(expression).interpretedExpression, evaluate("1/(2+3)").interpretedExpression);
	}
	for (const expression of ["inv 30s", "30s inv", "inv 3 m / 4 s * 7 g"]) {
		const inner = expression.replace(/^inv\s+|\s+inv$/g, "");
		assert.deepEqual(evaluate(expression), evaluate(`1/(${inner})`));
	}
	assert.equal(calculatorExpressionUsesCurrency("inv 2 USD"), true);
	assert.equal(evaluateCalculatorExpression("inv 0"), null);
	assert.equal(isCalculatorExpressionCandidate("inv"), false);
	assert.equal(isCalculatorExpressionCandidate("invoice"), false);
});

test("uses exact decimal arithmetic", () => {
	const variables = { zzz: "2384 m/s", toto: "1/(23 km/h) * e * pi*c", v2: "zzz * 2", period: "2w", fee: "2 USD" };
	for (const [query, expanded] of [["2 * zzz in km/h", "2 * (2384 m/s) in km/h"], ["toto", "1/(23 km/h) * e * pi*c"], ["v2 in m/s", "4768m/s in m/s"], ["inv period in Hz", "inv 2w in Hz"]]) {
		assert.equal(isCalculatorExpressionCandidate(query, variables), true);
		assert.equal(evaluateCalculatorExpression(query, null, undefined, variables).value, evaluate(expanded).value);
	}
	assert.equal(calculatorExpressionUsesCurrency("fee * 3", variables), true);
	assert.equal(evaluateCalculatorExpression("zzz", null, undefined, {}), null);
	assert.throws(() => expandCalculatorVariables("a", { a: "b", b: "a" }), /Circular/);
	assert.equal(evaluateCalculatorExpression("a", null, undefined, { a: "a" }), null);
	assert.equal(expandCalculatorVariables("1e3 + 2e-3", { e3: "9" }), "1e3 + 2e-3");
	assert.equal(validateCalculatorVariableName("zzz"), null);
	for (const name of ["pi", "c", "m", "month", "now", "mod", "1foo"]) assert.ok(validateCalculatorVariableName(name), name);
	for (const [expression, expected] of [
		["10 mod 3", "1"], ["10 mod (2 + 1)", "1"],
		["10%3", "1"], ["10 % .3", "0.1"], ["20 % 6 * 2", "4"],
		["7%of 293", "20.51"], ["7%of293", "20.51"],
		["7%of 200 + 100", "114"], ["7%of (200 + 100)", "21"],
		["100 / 2%of 10", "5"], ["7%of 2^3", "0.56"],
		["50% (2 + 1)", "1.5"], ["50% -2", "-1.5"],
		["10 mod -3", "1"], ["50% 2", "0"],
		["7%OF 293", "20.51"], ["10 MOD 3", "1"],
	]) {
		assert.equal(isCalculatorExpressionCandidate(expression), true, expression);
		assert.equal(evaluate(expression).value, expected, expression);
	}
	assert.equal(evaluate("50% pi").value, evaluate("0.5 * pi").value);
	assert.equal(evaluate("7%of 200kg in kg").value, "14");
	assert.equal(evaluate("10m mod 300cm in m").value, "1");
	assert.equal(evaluateCalculatorExpression("10m mod 3s"), null);
	for (const invalid of ["10 mod", "7%of", "10 % 0"]) {
		assert.equal(evaluateCalculatorExpression(invalid), null);
	}
	assert.equal(isCalculatorExpressionCandidate("50%"), true);
	assert.equal(evaluate("%").value, "0.01");
	assert.equal(evaluate("50%").value, "0.5");
	assert.equal(evaluate("200 * 10%").value, "20");
	assert.equal(evaluate("0.25 in %").value, "25");
	assert.equal(evaluate("(20 + 30)%").value, "0.5");
	assert.equal(evaluate("50% * 2h in h").value, "1");
	assert.equal(evaluate("100 + 10%").value, "100.1");
	for (const alias of ["month", "months", "mo"]) {
		assert.equal(evaluateCalculatorExpression(`1 ${alias} in d`), null);
		assert.equal(evaluateCalculatorExpression(`1 ${alias} in d`, null, "30").value, "30");
		assert.equal(evaluateCalculatorExpression(`1 ${alias} in d`, null, "30.4375").value, "30.4375");
	}
	assert.equal(evaluateCalculatorExpression("60d in month", null, "30").value, "2");
	assert.notEqual(evaluateCalculatorExpression("60d in month", null, "30.4375").value, "2");
	assert.equal(evaluateCalculatorExpression("1/month in 1/d", null, "30").value, evaluateCalculatorExpression("1/(30d) in 1/d").value);
	assert.equal(evaluateDateCalculation("2026-01-01 + 1month", undefined, new Date(2026, 0, 1), "30").value, "2026-01-31");
	assert.equal(evaluateDateCalculation("2026-01-01 + 1month", undefined, new Date(2026, 0, 1), "30.4375").value, "2026-01-31 10:30");
	assert.equal(evaluate("(824km/130km/h) in hmin").formattedValue, "6h 20min 18s");
	assert.equal(evaluate("1j in hmin").formattedValue, "1j");
	assert.equal(evaluate("0s in hmin").formattedValue, "0ms");
	assert.equal(evaluate("-90s in hmin").formattedValue, "−1min 30s");
	assert.equal(evaluate("1.234s in hmin").formattedValue, "1s 234ms");
	assert.equal(evaluateCalculatorExpression("1m in hmin"), null);
	assert.equal(evaluate("3661s in hmin").displayParts[2].small, true);
	assert.equal(evaluate("26**8").value, "208827064576");
	assert.equal(evaluate("26^8").formattedValue, "208827064576");
	assert.equal(evaluate("0.1 + 0.2").value, "0.3");
});

test("recognizes complete calculator input without evaluating it", () => {
	assert.equal(isCalculatorExpressionCandidate("exp(40)"), true);
	assert.equal(isCalculatorExpressionCandidate("26**8"), true);
	assert.equal(isCalculatorExpressionCandidate("3 m / 4 s * 7 g"), true);
	assert.equal(isCalculatorExpressionCandidate("26**"), false);
	assert.equal(isCalculatorExpressionCandidate("calendar"), false);
	assert.equal(isCalculatorExpressionCandidate("btc in $"), true);
});

test("converts EUR, USD and BTC as case-insensitive units", () => {
	assert.equal(evaluateCurrency("btc in $").value, "20000");
	assert.equal(evaluateCurrency("BTC in usd").formattedValue, "20000");
	assert.equal(evaluateCurrency("€ in USD").value, "2");
	assert.equal(evaluateCurrency("100 $ in eur").value, "50");
	assert.equal(evaluateCurrency("2 btc + 10000 EUR in USD").value, "60000");
	assert.equal(evaluateCalculatorExpression("BTC in USD"), null);
	assert.equal(calculatorExpressionUsesCurrency("3 m in cm"), false);
	assert.equal(calculatorExpressionUsesCurrency("3 Btc in €"), true);

	const result = evaluateCurrency("btc in $");
	assert.deepEqual(result.exchangeRateInfo, {
		summary: "1 BTC = 20000 USD",
		fetchedAt: currencyRates.fetchedAt,
		source: "Coinbase",
	});
});

test("displays rounded Bitcoin reference rates in the same direction", () => {
	const rates = { ...currencyRates, rates: { EUR: "1", USD: "1.23456", BTC: "0.00003" } };
	for (const [query, summary] of [
		["BTC in USD", "1 BTC = 41152 USD"],
		["USD in BTC", "1 BTC = 41152 USD"],
		["€ in btc", "1 BTC = 33333 EUR"],
		["btc in €", "1 BTC = 33333 EUR"],
		["2 btc", "1 BTC = 33333 EUR"],
	]) {
		assert.equal(evaluateCalculatorExpression(query, rates)?.exchangeRateInfo?.summary, summary, query);
	}
	assert.equal(evaluateCurrency("USD in BTC").value, "0.00005");
});

test("handles first-character constants, units, and currency symbols", () => {
	for (const input of ["e", "E", "s", "d", "$", "€"]) {
		assert.equal(isCalculatorExpressionCandidate(input), true, input);
		assert.equal(
			calculatorExpressionUsesCurrency(input),
			input === "$" || input === "€",
			input,
		);
		assert.ok(evaluateCalculatorExpression(input, currencyRates), input);
	}
	for (const input of ["r", "u", "S", "D"]) {
		assert.equal(isCalculatorExpressionCandidate(input), false, input);
		assert.equal(calculatorExpressionUsesCurrency(input), false, input);
	}
	assert.equal(evaluate("e").formattedValue, "2.71828182845905");
	assert.equal(evaluate("E").formattedValue, "2.71828182845905");
	assert.equal(evaluate("s").targetUnit, "s");
	assert.equal(evaluate("d").targetUnit, "d");
	assert.equal(evaluateCurrency("$").targetUnit, "USD");
	assert.equal(evaluateCurrency("€").targetUnit, "EUR");
	assert.equal(evaluateCalculatorExpression("$"), null);
	assert.equal(evaluateCalculatorExpression("€"), null);
});

test("validates the public Coinbase rate payload", () => {
	assert.deepEqual(
		parseCoinbaseCurrencyRates(
			{
				data: {
					currency: "EUR",
					rates: { EUR: "1.0", USD: "1.25", BTC: "0.00002" },
				},
			},
			currencyRates.fetchedAt,
		),
		{
			base: "EUR",
			rates: { EUR: "1.0", USD: "1.25", BTC: "0.00002" },
			fetchedAt: currencyRates.fetchedAt,
			source: "Coinbase",
		},
	);
	assert.throws(() =>
		parseCoinbaseCurrencyRates({
			data: { currency: "EUR", rates: { EUR: "1", USD: "nope" } },
		}),
	);
});

test("applies conventional operator precedence", () => {
	assert.equal(evaluate("2 + 3 * 4").value, "14");
	assert.equal(evaluate("(2 + 3) * 4").value, "20");
	assert.equal(evaluate("-2^2").value, "-4");
	assert.equal(evaluate("(-2)^2").value, "4");
	assert.equal(evaluate("2^3^2").value, "512");
	assert.equal(evaluate("10 % 3").value, "1");
	assert.equal(evaluate("1 / 2 pi").formattedValue, "0.159154943091895");
});

test("groups juxtaposed quantities before explicit multiplication and division", () => {
	const result = evaluate("3 m / 4 s * 7 g");
	assert.equal(result.value, "0.00525");
	assert.equal(result.targetUnit, "kg*m/s");

	const parenthesized = evaluate("3 m / (4 s * 7 g)");
	assert.equal(parenthesized.targetUnit, "m/(kg*s)");
	assert.equal(parenthesized.formattedValue, "107.142857142857");
});

test("keeps compact compound units attached to their coefficient", () => {
	const grouped = evaluate("1/(30s) / 900km/h");
	assert.equal(grouped.targetUnit, "m^-1");
	assert.equal(
		grouped.interpretedExpression,
		"(1 / (30 × s)) / (900 × (km / h))",
	);
	assert.ok(Math.abs(Number(grouped.value) - 1 / 7500) < 1e-18);

	const groupedWithCoefficientSpace = evaluate("1/(30s) / 900 km/h");
	assert.equal(groupedWithCoefficientSpace.targetUnit, "m^-1");
	assert.ok(
		Math.abs(Number(groupedWithCoefficientSpace.value) - 1 / 7500) < 1e-18,
	);

	const explicitlySpaced = evaluate("1/(30s) / 900km / h");
	assert.equal(explicitlySpaced.targetUnit, "m^-1*s^-2");
});

test("uses negative powers when a result has only inverse dimensions", () => {
	assert.equal(evaluate("1/m").targetUnit, "m^-1");
	assert.equal(evaluate("1/(kg*s)").targetUnit, "kg^-1*s^-1");
	assert.equal(evaluate("m/(kg*s)").targetUnit, "m/(kg*s)");
});

test("shows the exact operator grouping used by the parser", () => {
	assert.equal(evaluate("2 + 3 * 4").interpretedExpression, "2 + (3 × 4)");
	assert.equal(evaluate("-2^2").interpretedExpression, "-(2 ^ 2)");
	assert.equal(evaluate("(-2)^2").interpretedExpression, "(-2) ^ 2");
	assert.equal(
		evaluate("3 m to cm").interpretedExpression,
		"3 × m → cm",
	);
});

test("parses slashes and powers identically inside and outside units", () => {
	const speed = evaluate("9m / 2h");
	assert.equal(speed.value, "0.00125");
	assert.equal(speed.targetUnit, "m/s");

	assert.equal(evaluate("2m^2").value, "2");
	assert.equal(evaluate("(2m)^2").value, "4");
	assert.equal(evaluate("m/m").value, "1");
});

test("converts compound and aliased units", () => {
	assert.equal(isCalculatorExpressionCandidate("1w"), true);
	assert.equal(evaluate("1w in d").value, "7");
	assert.equal(evaluate("2 w in j").value, "14");
	assert.equal(evaluate("14d in w").value, "2");
	assert.equal(evaluate("1 W in W").value, "1");
	assert.equal(isCalculatorExpressionCandidate("1j"), true);
	assert.equal(evaluate("1j in h").value, "24");
	assert.equal(evaluate("2 j in s").value, "172800");
	assert.equal(evaluate("48 h in j").value, "2");
	const force = evaluate("5 kg * 9.81 m/s² in kN");
	assert.equal(force.value, "0.04905");
	assert.equal(force.targetUnit, "kN");

	const inches = evaluate("3 in to cm");
	assert.equal(inches.value, "7.62");
	assert.equal(inches.targetUnit, "cm");
});

test("applies dimensional rules to functions", () => {
	const squareRoot = evaluate("sqrt(9 m^2)");
	assert.equal(squareRoot.value, "3");
	assert.equal(squareRoot.targetUnit, "m");
	assert.equal(evaluate("sin(90 deg)").value, "1");
	assert.equal(evaluate("min(2m, 300cm)").value, "2");

	assert.equal(evaluateCalculatorExpression("1 m + 1 s"), null);
	assert.equal(evaluateCalculatorExpression("2 m ^ 0.5"), null);
});
