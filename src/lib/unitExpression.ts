import Big from "big.js";

type Dimensions = readonly [number, number, number, number, number];

type Quantity = {
	value: Big;
	dimensions: Dimensions;
	hasUnit: boolean;
};

type Token =
	| { type: "number"; value: string }
	| { type: "identifier"; value: string }
	| {
			type: "operator";
			value: "+" | "-" | "*" | "/" | "%" | "^";
	  }
	| { type: "leftParen" }
	| { type: "rightParen" }
	| { type: "comma" };

export type CalculatorExpressionResult = {
	expression: string;
	targetUnit: string;
	value: string;
	formattedValue: string;
	hasUnits: boolean;
};

export type UnitExpressionResult = CalculatorExpressionResult;

const DIMENSIONLESS: Dimensions = [0, 0, 0, 0, 0];
const MASS: Dimensions = [1, 0, 0, 0, 0];
const LENGTH: Dimensions = [0, 1, 0, 0, 0];
const TIME: Dimensions = [0, 0, 1, 0, 0];
const CURRENT: Dimensions = [0, 0, 0, 1, 0];
const ANGLE: Dimensions = [0, 0, 0, 0, 1];

Big.DP = 40;
Big.RM = Big.roundHalfEven;
Big.strict = true;

const quantity = (
	value: string | Big,
	dimensions: Dimensions,
	hasUnit = false,
): Quantity => ({
	value: typeof value === "string" ? new Big(value) : value,
	dimensions,
	hasUnit,
});

const unit = (value: string | Big, dimensions: Dimensions) =>
	quantity(value, dimensions, true);

export function normalizeCalculatorExpression(input: string) {
	return input.replace(/\*\*/g, "^");
}

const SPEED_OF_LIGHT_IN_METERS_PER_SECOND = 299_792_458;

const PI = "3.141592653589793238462643383279502884197";
const E = "2.718281828459045235360287471352662497757";

const derivedDimensions = (
	mass: number,
	length: number,
	time: number,
	current = 0,
	angle = 0,
): Dimensions => [mass, length, time, current, angle];

const UNITS: Record<string, Quantity> = {
	// Length
	m: unit("1", LENGTH),
	km: unit("1000", LENGTH),
	cm: unit("0.01", LENGTH),
	mm: unit("0.001", LENGTH),
	um: unit("0.000001", LENGTH),
	nm: unit("0.000000001", LENGTH),
	in: unit("0.0254", LENGTH),
	ft: unit("0.3048", LENGTH),
	yd: unit("0.9144", LENGTH),
	mi: unit("1609.344", LENGTH),

	// Mass
	kg: unit("1", MASS),
	g: unit("0.001", MASS),
	mg: unit("0.000001", MASS),
	ug: unit("0.000000001", MASS),
	lb: unit("0.45359237", MASS),
	oz: unit("0.028349523125", MASS),
	t: unit("1000", MASS),

	// Time
	s: unit("1", TIME),
	ms: unit("0.001", TIME),
	min: unit("60", TIME),
	h: unit("3600", TIME),
	d: unit("86400", TIME),
	wk: unit("604800", TIME),
	mo: unit("2629800", TIME),
	yr: unit("31557600", TIME),

	// Electric current
	A: unit("1", CURRENT),
	mA: unit("0.001", CURRENT),

	// Volume
	L: unit("0.001", derivedDimensions(0, 3, 0)),
	mL: unit("0.000001", derivedDimensions(0, 3, 0)),

	// Angle (tracked separately so ratios such as m/m are not mistaken for radians)
	rad: unit("1", ANGLE),
	deg: unit(new Big(PI).div("180"), ANGLE),

	// Speed
	kph: unit(new Big("1000").div("3600"), derivedDimensions(0, 1, -1)),
	mph: unit(new Big("1609.344").div("3600"), derivedDimensions(0, 1, -1)),
	knot: unit(new Big("1852").div("3600"), derivedDimensions(0, 1, -1)),

	// Frequency
	Hz: unit("1", derivedDimensions(0, 0, -1)),
	kHz: unit("1000", derivedDimensions(0, 0, -1)),
	MHz: unit("1000000", derivedDimensions(0, 0, -1)),

	// Force
	N: unit("1", derivedDimensions(1, 1, -2)),
	mN: unit("0.001", derivedDimensions(1, 1, -2)),
	kN: unit("1000", derivedDimensions(1, 1, -2)),
	MN: unit("1000000", derivedDimensions(1, 1, -2)),

	// Pressure
	Pa: unit("1", derivedDimensions(1, -1, -2)),
	kPa: unit("1000", derivedDimensions(1, -1, -2)),
	MPa: unit("1000000", derivedDimensions(1, -1, -2)),
	bar: unit("100000", derivedDimensions(1, -1, -2)),
	psi: unit("6894.757293168", derivedDimensions(1, -1, -2)),

	// Energy
	J: unit("1", derivedDimensions(1, 2, -2)),
	kJ: unit("1000", derivedDimensions(1, 2, -2)),
	MJ: unit("1000000", derivedDimensions(1, 2, -2)),
	Wh: unit("3600", derivedDimensions(1, 2, -2)),
	kWh: unit("3600000", derivedDimensions(1, 2, -2)),

	// Power
	W: unit("1", derivedDimensions(1, 2, -3)),
	kW: unit("1000", derivedDimensions(1, 2, -3)),
	MW: unit("1000000", derivedDimensions(1, 2, -3)),
};

const EXPRESSION_CONSTANTS: Record<string, Quantity> = {
	pi: quantity(PI, DIMENSIONLESS),
	e: quantity(E, DIMENSIONLESS),
	c: unit(
		SPEED_OF_LIGHT_IN_METERS_PER_SECOND.toString(),
		derivedDimensions(0, 1, -1),
	),
};

const UNIT_ALIASES: Record<string, string> = {
	meter: "m",
	meters: "m",
	metre: "m",
	metres: "m",
	kilometer: "km",
	kilometers: "km",
	kilometre: "km",
	kilometres: "km",
	centimeter: "cm",
	centimeters: "cm",
	centimetre: "cm",
	centimetres: "cm",
	millimeter: "mm",
	millimeters: "mm",
	millimetre: "mm",
	millimetres: "mm",
	inch: "in",
	inches: "in",
	foot: "ft",
	feet: "ft",
	yard: "yd",
	yards: "yd",
	mile: "mi",
	miles: "mi",
	gram: "g",
	grams: "g",
	kilogram: "kg",
	kilograms: "kg",
	pound: "lb",
	pounds: "lb",
	lbs: "lb",
	ounce: "oz",
	ounces: "oz",
	tonne: "t",
	tonnes: "t",
	second: "s",
	seconds: "s",
	sec: "s",
	millisecond: "ms",
	milliseconds: "ms",
	minute: "min",
	minutes: "min",
	hour: "h",
	hours: "h",
	day: "d",
	days: "d",
	week: "wk",
	weeks: "wk",
	month: "mo",
	months: "mo",
	y: "yr",
	year: "yr",
	years: "yr",
	liter: "L",
	liters: "L",
	litre: "L",
	litres: "L",
	milliliter: "mL",
	milliliters: "mL",
	millilitre: "mL",
	millilitres: "mL",
	degree: "deg",
	degrees: "deg",
	"°": "deg",
	hz: "Hz",
	khz: "kHz",
	mhz: "MHz",
	newton: "N",
	newtons: "N",
	kn: "kN",
	kilonewton: "kN",
	kilonewtons: "kN",
	pa: "Pa",
	kpa: "kPa",
	mpa: "MPa",
	pascal: "Pa",
	pascals: "Pa",
	joule: "J",
	joules: "J",
	kilojoule: "kJ",
	kilojoules: "kJ",
	watt: "W",
	watts: "W",
	kilowatt: "kW",
	kilowatts: "kW",
	l: "L",
	ml: "mL",
};

function normalizeExpression(input: string) {
	return normalizeCalculatorExpression(input)
		.trim()
		.replace(/π/g, "pi")
		.replace(/[×·]/g, "*")
		.replace(/÷/g, "/")
		.replace(/²/g, "^2")
		.replace(/³/g, "^3")
		.replace(/⁴/g, "^4")
		.replace(/\bper\b/gi, "/")
		.replace(/(\d),(?=\d{3}(?:\D|$))/g, "$1")
		.replace(/\s+/g, " ");
}

function addDimensions(a: Dimensions, b: Dimensions): Dimensions {
	return [
		a[0] + b[0],
		a[1] + b[1],
		a[2] + b[2],
		a[3] + b[3],
		a[4] + b[4],
	];
}

function subtractDimensions(a: Dimensions, b: Dimensions): Dimensions {
	return [
		a[0] - b[0],
		a[1] - b[1],
		a[2] - b[2],
		a[3] - b[3],
		a[4] - b[4],
	];
}

function scaleDimensions(dimensions: Dimensions, power: number): Dimensions {
	return [
		dimensions[0] * power,
		dimensions[1] * power,
		dimensions[2] * power,
		dimensions[3] * power,
		dimensions[4] * power,
	];
}

function dimensionsMatch(a: Dimensions, b: Dimensions) {
	return a.every((value, index) => Math.abs(value - b[index]) < 1e-10);
}

function isDimensionless(dimensions: Dimensions) {
	return dimensionsMatch(dimensions, DIMENSIONLESS);
}

function resolveIdentifier(rawIdentifier: string): Quantity {
	const constant = EXPRESSION_CONSTANTS[rawIdentifier.toLowerCase()];
	if (constant) {
		return constant;
	}

	const direct = UNITS[rawIdentifier];
	if (direct) {
		return direct;
	}

	const alias = UNIT_ALIASES[rawIdentifier.toLowerCase()];
	if (alias && UNITS[alias]) {
		return UNITS[alias];
	}

	throw new Error(`Unknown identifier: ${rawIdentifier}`);
}

function tokenize(input: string): Token[] {
	const tokens: Token[] = [];
	const tokenPattern =
		/\s*(?:(\d+(?:\.\d*)?(?:[eE][+-]?\d+)?|\.\d+(?:[eE][+-]?\d+)?)|([A-Za-zµμ°]+)|([()+\-*/^%,]))/y;
	let offset = 0;

	while (offset < input.length) {
		tokenPattern.lastIndex = offset;
		const match = tokenPattern.exec(input);
		if (!match) {
			throw new Error(`Unexpected token at ${input.slice(offset)}`);
		}

		if (match[1]) {
			tokens.push({ type: "number", value: match[1] });
		} else if (match[2]) {
			tokens.push({
				type: "identifier",
				value: match[2].replace(/[µμ]/g, "u"),
			});
		} else if (match[3] === "(") {
			tokens.push({ type: "leftParen" });
		} else if (match[3] === ")") {
			tokens.push({ type: "rightParen" });
		} else if (match[3] === ",") {
			tokens.push({ type: "comma" });
		} else {
			tokens.push({
				type: "operator",
				value: match[3] as "+" | "-" | "*" | "/" | "%" | "^",
			});
		}

		offset = tokenPattern.lastIndex;
	}

	return tokens;
}

const FUNCTION_NAMES = new Set([
	"abs",
	"acos",
	"asin",
	"atan",
	"atan2",
	"cbrt",
	"ceil",
	"cos",
	"exp",
	"floor",
	"hypot",
	"ln",
	"log",
	"log10",
	"max",
	"min",
	"mod",
	"pow",
	"round",
	"sign",
	"sin",
	"sqrt",
	"tan",
	"trunc",
]);

function assertArgumentCount(
	name: string,
	args: Quantity[],
	minimum: number,
	maximum = minimum,
) {
	if (args.length < minimum || args.length > maximum) {
		throw new Error(`${name} expects ${minimum}-${maximum} arguments`);
	}
}

function assertDimensionless(value: Quantity, operation: string) {
	if (!isDimensionless(value.dimensions)) {
		throw new Error(`${operation} expects a dimensionless value`);
	}
}

function assertMatchingDimensions(values: Quantity[], operation: string) {
	const first = values[0];
	if (
		first == null ||
		values.some((value) => !dimensionsMatch(value.dimensions, first.dimensions))
	) {
		throw new Error(`${operation} expects compatible dimensions`);
	}
}

function toFiniteNumber(value: Big, operation: string) {
	const result = Number(value.toString());
	if (!Number.isFinite(result)) {
		throw new Error(`${operation} is outside the supported range`);
	}
	return result;
}

function approximate(
	value: Quantity,
	operation: string,
	callback: (input: number) => number,
	allowAngle = false,
) {
	if (
		!isDimensionless(value.dimensions) &&
		!(allowAngle && dimensionsMatch(value.dimensions, ANGLE))
	) {
		throw new Error(
			allowAngle
				? `${operation} expects an angle or dimensionless value`
				: `${operation} expects a dimensionless value`,
		);
	}
	const result = callback(toFiniteNumber(value.value, operation));
	if (!Number.isFinite(result)) {
		throw new Error(`${operation} has no finite result`);
	}
	return quantity(result.toString(), DIMENSIONLESS);
}

const MAX_INTEGER_EXPONENT = 10_000;

function power(base: Quantity, exponent: Quantity): Quantity {
	assertDimensionless(exponent, "Power");
	const exponentAsNumber = toFiniteNumber(exponent.value, "Power");
	const integerExponent =
		exponent.value.round(0, Big.roundDown).eq(exponent.value) &&
		Number.isSafeInteger(exponentAsNumber) &&
		Math.abs(exponentAsNumber) <= MAX_INTEGER_EXPONENT;

	if (!isDimensionless(base.dimensions) && !integerExponent) {
		throw new Error("Dimensioned values require a small integer exponent");
	}

	const result = integerExponent
		? base.value.pow(exponentAsNumber)
		: new Big(
				Math.pow(
					toFiniteNumber(base.value, "Power"),
					exponentAsNumber,
				).toString(),
			);
	return quantity(
		result,
		integerExponent
			? scaleDimensions(base.dimensions, exponentAsNumber)
			: DIMENSIONLESS,
		base.hasUnit,
	);
}

function evaluateFunction(name: string, args: Quantity[]): Quantity {
	switch (name) {
		case "abs": {
			assertArgumentCount(name, args, 1);
			return quantity(args[0].value.abs(), args[0].dimensions, args[0].hasUnit);
		}
		case "sqrt": {
			assertArgumentCount(name, args, 1);
			return quantity(
				args[0].value.sqrt(),
				scaleDimensions(args[0].dimensions, 0.5),
				args[0].hasUnit,
			);
		}
		case "cbrt": {
			assertArgumentCount(name, args, 1);
			const numeric = Math.cbrt(toFiniteNumber(args[0].value, name));
			return quantity(
				numeric.toString(),
				scaleDimensions(args[0].dimensions, 1 / 3),
				args[0].hasUnit,
			);
		}
		case "floor":
		case "ceil":
		case "trunc": {
			assertArgumentCount(name, args, 1);
			const input = args[0];
			const mode =
				name === "trunc"
					? Big.roundDown
					: name === "floor"
						? input.value.lt("0")
							? Big.roundUp
							: Big.roundDown
						: input.value.lt("0")
							? Big.roundDown
							: Big.roundUp;
			return quantity(
				input.value.round(0, mode),
				input.dimensions,
				input.hasUnit,
			);
		}
		case "round": {
			assertArgumentCount(name, args, 1, 2);
			const decimalPlaces = args[1]
				? toFiniteNumber(args[1].value, name)
				: 0;
			if (
				!Number.isSafeInteger(decimalPlaces) ||
				decimalPlaces < 0 ||
				decimalPlaces > 100
			) {
				throw new Error("round precision must be an integer from 0 to 100");
			}
			if (args[1]) assertDimensionless(args[1], name);
			return quantity(
				args[0].value.round(decimalPlaces, Big.roundHalfUp),
				args[0].dimensions,
				args[0].hasUnit,
			);
		}
		case "sign": {
			assertArgumentCount(name, args, 1);
			return quantity(
				args[0].value.eq("0") ? "0" : args[0].value.lt("0") ? "-1" : "1",
				DIMENSIONLESS,
			);
		}
		case "min":
		case "max": {
			assertArgumentCount(name, args, 1, Number.MAX_SAFE_INTEGER);
			assertMatchingDimensions(args, name);
			return args.slice(1).reduce((selected, candidate) => {
				const replace =
					name === "min"
						? candidate.value.lt(selected.value)
						: candidate.value.gt(selected.value);
				return replace ? candidate : selected;
			}, args[0]);
		}
		case "hypot": {
			assertArgumentCount(name, args, 1, Number.MAX_SAFE_INTEGER);
			assertMatchingDimensions(args, name);
			const sum = args.reduce(
				(total, value) => total.plus(value.value.times(value.value)),
				new Big("0"),
			);
			return quantity(sum.sqrt(), args[0].dimensions, args.some((arg) => arg.hasUnit));
		}
		case "pow": {
			assertArgumentCount(name, args, 2);
			return power(args[0], args[1]);
		}
		case "mod": {
			assertArgumentCount(name, args, 2);
			assertMatchingDimensions(args, name);
			return quantity(
				args[0].value.mod(args[1].value),
				args[0].dimensions,
				args.some((arg) => arg.hasUnit),
			);
		}
		case "sin":
			assertArgumentCount(name, args, 1);
			return approximate(args[0], name, Math.sin, true);
		case "cos":
			assertArgumentCount(name, args, 1);
			return approximate(args[0], name, Math.cos, true);
		case "tan":
			assertArgumentCount(name, args, 1);
			return approximate(args[0], name, Math.tan, true);
		case "asin":
			assertArgumentCount(name, args, 1);
			return quantity(
				approximate(args[0], name, Math.asin).value,
				ANGLE,
				true,
			);
		case "acos":
			assertArgumentCount(name, args, 1);
			return quantity(
				approximate(args[0], name, Math.acos).value,
				ANGLE,
				true,
			);
		case "atan":
			assertArgumentCount(name, args, 1);
			return quantity(
				approximate(args[0], name, Math.atan).value,
				ANGLE,
				true,
			);
		case "atan2": {
			assertArgumentCount(name, args, 2);
			assertMatchingDimensions(args, name);
			const result = Math.atan2(
				toFiniteNumber(args[0].value, name),
				toFiniteNumber(args[1].value, name),
			);
			return quantity(result.toString(), ANGLE, true);
		}
		case "exp":
			assertArgumentCount(name, args, 1);
			return approximate(args[0], name, Math.exp);
		case "ln":
		case "log":
			assertArgumentCount(name, args, 1);
			return approximate(args[0], name, Math.log);
		case "log10":
			assertArgumentCount(name, args, 1);
			return approximate(args[0], name, Math.log10);
		default:
			throw new Error(`Unknown function: ${name}`);
	}
}

// Precedence from lowest to highest: +/-, explicit */%, juxtaposition,
// unary signs, then right-associative powers. Juxtaposition deliberately binds
// tightly so `9m / 2h` means `(9 m) / (2 h)` and `2 pi` is one coefficient.
class QuantityParser {
	private index = 0;
	private readonly tokens: Token[];

	constructor(tokens: Token[]) {
		this.tokens = tokens;
	}

	parse() {
		const result = this.parseAdditive();
		if (this.index !== this.tokens.length) {
			throw new Error("Unexpected trailing expression");
		}
		return result;
	}

	private parseAdditive(): Quantity {
		let result = this.parseMultiplicative();
		while (this.matchesOperator("+") || this.matchesOperator("-")) {
			const operator = (
				this.tokens[this.index] as Extract<Token, { type: "operator" }>
			).value;
			this.index += 1;
			const right = this.parseMultiplicative();
			if (!dimensionsMatch(result.dimensions, right.dimensions)) {
				throw new Error("Cannot add quantities with different dimensions");
			}
			result = quantity(
				operator === "+"
					? result.value.plus(right.value)
					: result.value.minus(right.value),
				result.dimensions,
				result.hasUnit || right.hasUnit,
			);
		}
		return result;
	}

	private parseMultiplicative(): Quantity {
		let result = this.parseImplicitMultiplicative();
		while (
			this.matchesOperator("*") ||
			this.matchesOperator("/") ||
			this.matchesOperator("%")
		) {
			const operator = (
				this.tokens[this.index] as Extract<Token, { type: "operator" }>
			).value;
			this.index += 1;
			const right = this.parseImplicitMultiplicative();
			if (operator === "%") {
				assertMatchingDimensions([result, right], "Remainder");
				result = quantity(
					result.value.mod(right.value),
					result.dimensions,
					result.hasUnit || right.hasUnit,
				);
			} else if (operator === "*") {
				result = quantity(
					result.value.times(right.value),
					addDimensions(result.dimensions, right.dimensions),
					result.hasUnit || right.hasUnit,
				);
			} else {
				result = quantity(
					result.value.div(right.value),
					subtractDimensions(result.dimensions, right.dimensions),
					result.hasUnit || right.hasUnit,
				);
			}
		}
		return result;
	}

	private parseImplicitMultiplicative(): Quantity {
		let result = this.parseUnary();
		while (this.canStartPrimary(this.tokens[this.index])) {
			const right = this.parseUnary();
			result = quantity(
				result.value.times(right.value),
				addDimensions(result.dimensions, right.dimensions),
				result.hasUnit || right.hasUnit,
			);
		}
		return result;
	}

	private parseUnary(): Quantity {
		if (this.matchesOperator("+")) {
			this.index += 1;
			return this.parseUnary();
		}
		if (this.matchesOperator("-")) {
			this.index += 1;
			const value = this.parseUnary();
			return quantity(value.value.neg(), value.dimensions, value.hasUnit);
		}
		return this.parsePower();
	}

	private parsePower(): Quantity {
		const base = this.parsePrimary();
		if (!this.matchesOperator("^")) {
			return base;
		}

		this.index += 1;
		return power(base, this.parseUnary());
	}

	private parsePrimary(): Quantity {
		const token = this.tokens[this.index];
		if (!token) {
			throw new Error("Unexpected end of expression");
		}

		if (token.type === "number") {
			this.index += 1;
			return quantity(token.value, DIMENSIONLESS);
		}

		if (token.type === "identifier") {
			this.index += 1;
			const normalizedName = token.value.toLowerCase();
			if (
				FUNCTION_NAMES.has(normalizedName) &&
				this.tokens[this.index]?.type === "leftParen"
			) {
				return this.parseFunctionCall(normalizedName);
			}
			return resolveIdentifier(token.value);
		}

		if (token.type === "leftParen") {
			this.index += 1;
			const value = this.parseAdditive();
			if (this.tokens[this.index]?.type !== "rightParen") {
				throw new Error("Missing closing parenthesis");
			}
			this.index += 1;
			return value;
		}

		throw new Error("Unexpected expression token");
	}

	private parseFunctionCall(name: string) {
		this.index += 1;
		const args: Quantity[] = [];
		if (this.tokens[this.index]?.type !== "rightParen") {
			while (true) {
				args.push(this.parseAdditive());
				if (this.tokens[this.index]?.type !== "comma") break;
				this.index += 1;
			}
		}
		if (this.tokens[this.index]?.type !== "rightParen") {
			throw new Error(`Missing closing parenthesis for ${name}`);
		}
		this.index += 1;
		return evaluateFunction(name, args);
	}

	private canStartPrimary(token: Token | undefined) {
		return (
			token?.type === "number" ||
			token?.type === "identifier" ||
			token?.type === "leftParen"
		);
	}

	private matchesOperator(
		operator: Extract<Token, { type: "operator" }>["value"],
	) {
		const token = this.tokens[this.index];
		return token?.type === "operator" && token.value === operator;
	}
}

function parseQuantity(input: string) {
	return new QuantityParser(tokenize(input)).parse();
}

type AutomaticUnitGroup = {
	dimensions: Dimensions;
	units: string[];
	fallback: string;
};

const AUTOMATIC_UNIT_GROUPS: AutomaticUnitGroup[] = [
	{ dimensions: MASS, units: ["t", "kg", "g", "mg", "ug"], fallback: "kg" },
	{
		dimensions: LENGTH,
		units: ["km", "m", "cm", "mm", "um", "nm"],
		fallback: "m",
	},
	{
		dimensions: TIME,
		units: ["yr", "mo", "wk", "d", "h", "min", "s", "ms"],
		fallback: "s",
	},
	{ dimensions: CURRENT, units: ["A", "mA"], fallback: "A" },
	{ dimensions: ANGLE, units: ["rad", "deg"], fallback: "rad" },
	{
		dimensions: derivedDimensions(0, 3, 0),
		units: ["m^3", "L", "mL"],
		fallback: "L",
	},
	{
		dimensions: derivedDimensions(0, 1, -1),
		units: ["m/s"],
		fallback: "m/s",
	},
	{
		dimensions: derivedDimensions(0, 0, -1),
		units: ["MHz", "kHz", "Hz"],
		fallback: "Hz",
	},
	{
		dimensions: derivedDimensions(1, 1, -2),
		units: ["MN", "kN", "N", "mN"],
		fallback: "N",
	},
	{
		dimensions: derivedDimensions(1, -1, -2),
		units: ["MPa", "kPa", "Pa"],
		fallback: "Pa",
	},
	{
		dimensions: derivedDimensions(1, 2, -2),
		units: ["MJ", "kJ", "J"],
		fallback: "J",
	},
	{
		dimensions: derivedDimensions(1, 2, -3),
		units: ["MW", "kW", "W"],
		fallback: "W",
	},
];

function formatExponent(value: number) {
	return Number.isInteger(value)
		? value.toString()
		: formatResult(new Big(value.toString()));
}

function formatBaseUnit(dimensions: Dimensions) {
	const names = ["kg", "m", "s", "A", "rad"];
	const numerator: string[] = [];
	const denominator: string[] = [];
	for (let index = 0; index < dimensions.length; index += 1) {
		const exponent = dimensions[index];
		if (exponent === 0) continue;
		const formatted =
			Math.abs(exponent) === 1
				? names[index]
				: `${names[index]}^${formatExponent(Math.abs(exponent))}`;
		if (exponent > 0) numerator.push(formatted);
		else denominator.push(formatted);
	}
	const top = numerator.length > 0 ? numerator.join("*") : "1";
	if (denominator.length === 0) return top;
	const bottom = denominator.join("*");
	return denominator.length === 1 ? `${top}/${bottom}` : `${top}/(${bottom})`;
}

function inferTargetUnit(source: Quantity) {
	const group = AUTOMATIC_UNIT_GROUPS.find(({ dimensions }) =>
		dimensionsMatch(source.dimensions, dimensions),
	);
	if (!group) {
		return {
			unit: formatBaseUnit(source.dimensions),
			quantity: unit("1", source.dimensions),
		};
	}

	if (source.value.eq("0")) {
		return { unit: group.fallback, quantity: parseQuantity(group.fallback) };
	}

	for (const unit of group.units) {
		const target = parseQuantity(unit);
		const converted = source.value.div(target.value).abs();
		if (converted.gte("1") && converted.lt("1000")) {
			return { unit, quantity: target };
		}
	}

	const edgeUnit =
		source.value
			.div(parseQuantity(group.units[0]).value)
			.abs()
			.gte("1000")
			? group.units[0]
			: group.units[group.units.length - 1];
	return { unit: edgeUnit, quantity: parseQuantity(edgeUnit) };
}

function formatResult(value: Big) {
	if (value.eq("0")) return "0";

	const absoluteValue = value.abs();
	if (absoluteValue.gte("1e12") || absoluteValue.lt("1e-9")) {
		return value
			.toExponential(14, Big.roundHalfEven)
			.replace(/(\.\d*?[1-9])0+(?=e)/, "$1")
			.replace(/\.0+(?=e)/, "");
	}

	return value.prec(15, Big.roundHalfEven).toFixed();
}

function splitConversionExpression(normalized: string) {
	let depth = 0;
	let separatorIndex = -1;

	for (let index = 0; index < normalized.length; index += 1) {
		const character = normalized[index];
		if (character === "(") depth += 1;
		else if (character === ")") depth = Math.max(0, depth - 1);
		else if (
			depth === 0 &&
			(normalized.slice(index, index + 4).toLowerCase() === " in " ||
				normalized.slice(index, index + 4).toLowerCase() === " to ") &&
			normalized.slice(index + 4).trim().length > 0
		) {
			separatorIndex = index;
		}
	}

	return separatorIndex < 0
		? { expression: normalized, targetUnit: "", hasExplicitTarget: false }
		: {
				expression: normalized.slice(0, separatorIndex).trim(),
				targetUnit: normalized.slice(separatorIndex + 4).trim(),
				hasExplicitTarget: true,
			};
}

function tokensFormCompleteCalculatorInput(tokens: Token[]) {
	if (tokens.length === 0) return false;

	let parenthesisDepth = 0;
	for (let index = 0; index < tokens.length; index += 1) {
		const token = tokens[index];
		if (token.type === "leftParen") {
			parenthesisDepth += 1;
			continue;
		}
		if (token.type === "rightParen") {
			parenthesisDepth -= 1;
			if (parenthesisDepth < 0) return false;
			continue;
		}
		if (token.type !== "identifier") continue;

		const normalizedName = token.value.toLowerCase();
		if (
			FUNCTION_NAMES.has(normalizedName) &&
			tokens[index + 1]?.type === "leftParen"
		) {
			continue;
		}

		try {
			resolveIdentifier(token.value);
		} catch {
			return false;
		}
	}

	const lastToken = tokens[tokens.length - 1];
	return (
		parenthesisDepth === 0 &&
		lastToken.type !== "operator" &&
		lastToken.type !== "leftParen" &&
		lastToken.type !== "comma"
	);
}

/**
 * Cheaply recognizes complete calculator-shaped input without evaluating it.
 * This lets the UI paint a loading state before an expensive calculation starts.
 */
export function isCalculatorExpressionCandidate(query: string) {
	const normalized = normalizeExpression(query);
	const { expression, targetUnit, hasExplicitTarget } =
		splitConversionExpression(normalized);
	if (!expression || (hasExplicitTarget && !targetUnit)) return false;

	try {
		if (!tokensFormCompleteCalculatorInput(tokenize(expression))) return false;
		return (
			!hasExplicitTarget ||
			tokensFormCompleteCalculatorInput(tokenize(targetUnit))
		);
	} catch {
		return false;
	}
}

export function evaluateCalculatorExpression(
	query: string,
): CalculatorExpressionResult | null {
	const normalized = normalizeExpression(query);
	const { expression, targetUnit, hasExplicitTarget } =
		splitConversionExpression(normalized);
	if (!expression || (hasExplicitTarget && !targetUnit)) return null;

	try {
		const source = parseQuantity(expression);
		if (!hasExplicitTarget && isDimensionless(source.dimensions)) {
			return {
				expression,
				targetUnit: "",
				value: source.value.toString(),
				formattedValue: formatResult(source.value),
				hasUnits: false,
			};
		}
		const inferredTarget = hasExplicitTarget ? null : inferTargetUnit(source);
		const resolvedTargetUnit = inferredTarget?.unit ?? targetUnit;
		const target = inferredTarget?.quantity ?? parseQuantity(targetUnit);
		if (
			!dimensionsMatch(source.dimensions, target.dimensions) ||
			target.value.eq("0")
		) {
			return null;
		}

		const value = source.value.div(target.value);
		return {
			expression,
			targetUnit: resolvedTargetUnit,
			value: value.toString(),
			formattedValue: formatResult(value),
			hasUnits: true,
		};
	} catch {
		return null;
	}
}

export const evaluateUnitExpression = evaluateCalculatorExpression;
