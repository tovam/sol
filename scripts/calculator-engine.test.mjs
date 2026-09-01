import assert from "node:assert/strict";
import test from "node:test";
import {
	evaluateCalculatorExpression,
	isCalculatorExpressionCandidate,
} from "../src/lib/unitExpression.ts";

function evaluate(expression) {
	const result = evaluateCalculatorExpression(expression);
	assert.ok(result, `Expected a result for: ${expression}`);
	return result;
}

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
	assert.equal(grouped.targetUnit, "1/m");
	assert.equal(
		grouped.interpretedExpression,
		"(1 / (30 × s)) / (900 × (km / h))",
	);
	assert.ok(Math.abs(Number(grouped.value) - 1 / 7500) < 1e-18);

	const groupedWithCoefficientSpace = evaluate("1/(30s) / 900 km/h");
	assert.equal(groupedWithCoefficientSpace.targetUnit, "1/m");
	assert.ok(
		Math.abs(Number(groupedWithCoefficientSpace.value) - 1 / 7500) < 1e-18,
	);

	const explicitlySpaced = evaluate("1/(30s) / 900km / h");
	assert.equal(explicitlySpaced.targetUnit, "1/(m*s^2)");
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
