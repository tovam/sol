import assert from "node:assert/strict";
import test from "node:test";
import {
	calculatorExpressionUsesCurrency,
	evaluateCalculatorExpression,
	isCalculatorExpressionCandidate,
} from "../src/lib/unitExpression.ts";
import { parseCoinbaseCurrencyRates } from "../src/lib/currencyRates.ts";

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
