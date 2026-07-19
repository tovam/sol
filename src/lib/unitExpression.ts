type Dimensions = readonly [number, number, number, number];

type Quantity = {
	value: number;
	dimensions: Dimensions;
};

type Token =
	| { type: "number"; value: number }
	| { type: "unit"; value: string }
	| {
			type: "operator";
			value: "+" | "-" | "*" | "/" | "^" | "implicitMultiply";
	  }
	| { type: "leftParen" }
	| { type: "rightParen" };

export type UnitExpressionResult = {
	expression: string;
	targetUnit: string;
	value: number;
	formattedValue: string;
};

const DIMENSIONLESS: Dimensions = [0, 0, 0, 0];
const MASS: Dimensions = [1, 0, 0, 0];
const LENGTH: Dimensions = [0, 1, 0, 0];
const TIME: Dimensions = [0, 0, 1, 0];
const CURRENT: Dimensions = [0, 0, 0, 1];

const quantity = (value: number, dimensions: Dimensions): Quantity => ({
	value,
	dimensions,
});

const derivedDimensions = (
	mass: number,
	length: number,
	time: number,
	current = 0,
): Dimensions => [mass, length, time, current];

const UNITS: Record<string, Quantity> = {
	// Length
	m: quantity(1, LENGTH),
	km: quantity(1_000, LENGTH),
	cm: quantity(0.01, LENGTH),
	mm: quantity(0.001, LENGTH),
	um: quantity(0.000_001, LENGTH),
	nm: quantity(0.000_000_001, LENGTH),
	in: quantity(0.0254, LENGTH),
	ft: quantity(0.3048, LENGTH),
	yd: quantity(0.9144, LENGTH),
	mi: quantity(1_609.344, LENGTH),

	// Mass
	kg: quantity(1, MASS),
	g: quantity(0.001, MASS),
	mg: quantity(0.000_001, MASS),
	ug: quantity(0.000_000_001, MASS),
	lb: quantity(0.45359237, MASS),
	oz: quantity(0.028349523125, MASS),
	t: quantity(1_000, MASS),

	// Time
	s: quantity(1, TIME),
	ms: quantity(0.001, TIME),
	min: quantity(60, TIME),
	h: quantity(3_600, TIME),
	d: quantity(86_400, TIME),
	wk: quantity(604_800, TIME),
	mo: quantity(2_629_800, TIME),
	yr: quantity(31_557_600, TIME),

	// Electric current
	A: quantity(1, CURRENT),
	mA: quantity(0.001, CURRENT),

	// Volume
	L: quantity(0.001, derivedDimensions(0, 3, 0)),
	mL: quantity(0.000_001, derivedDimensions(0, 3, 0)),

	// Angle (dimensionless in SI)
	rad: quantity(1, DIMENSIONLESS),
	deg: quantity(Math.PI / 180, DIMENSIONLESS),

	// Speed
	kph: quantity(1_000 / 3_600, derivedDimensions(0, 1, -1)),
	mph: quantity(1_609.344 / 3_600, derivedDimensions(0, 1, -1)),
	knot: quantity(1_852 / 3_600, derivedDimensions(0, 1, -1)),

	// Frequency
	Hz: quantity(1, derivedDimensions(0, 0, -1)),
	kHz: quantity(1_000, derivedDimensions(0, 0, -1)),
	MHz: quantity(1_000_000, derivedDimensions(0, 0, -1)),

	// Force
	N: quantity(1, derivedDimensions(1, 1, -2)),
	mN: quantity(0.001, derivedDimensions(1, 1, -2)),
	kN: quantity(1_000, derivedDimensions(1, 1, -2)),
	MN: quantity(1_000_000, derivedDimensions(1, 1, -2)),

	// Pressure
	Pa: quantity(1, derivedDimensions(1, -1, -2)),
	kPa: quantity(1_000, derivedDimensions(1, -1, -2)),
	MPa: quantity(1_000_000, derivedDimensions(1, -1, -2)),
	bar: quantity(100_000, derivedDimensions(1, -1, -2)),
	psi: quantity(6_894.757293168, derivedDimensions(1, -1, -2)),

	// Energy
	J: quantity(1, derivedDimensions(1, 2, -2)),
	kJ: quantity(1_000, derivedDimensions(1, 2, -2)),
	MJ: quantity(1_000_000, derivedDimensions(1, 2, -2)),
	Wh: quantity(3_600, derivedDimensions(1, 2, -2)),
	kWh: quantity(3_600_000, derivedDimensions(1, 2, -2)),

	// Power
	W: quantity(1, derivedDimensions(1, 2, -3)),
	kW: quantity(1_000, derivedDimensions(1, 2, -3)),
	MW: quantity(1_000_000, derivedDimensions(1, 2, -3)),
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
	return input
		.trim()
		.replace(/[×·]/g, "*")
		.replace(/÷/g, "/")
		.replace(/²/g, "^2")
		.replace(/³/g, "^3")
		.replace(/⁴/g, "^4")
		.replace(/\bper\b/gi, "/")
		.replace(/\s+/g, " ");
}

function addDimensions(a: Dimensions, b: Dimensions): Dimensions {
	return [a[0] + b[0], a[1] + b[1], a[2] + b[2], a[3] + b[3]];
}

function subtractDimensions(a: Dimensions, b: Dimensions): Dimensions {
	return [a[0] - b[0], a[1] - b[1], a[2] - b[2], a[3] - b[3]];
}

function scaleDimensions(dimensions: Dimensions, power: number): Dimensions {
	return [
		dimensions[0] * power,
		dimensions[1] * power,
		dimensions[2] * power,
		dimensions[3] * power,
	];
}

function dimensionsMatch(a: Dimensions, b: Dimensions) {
	return a.every((value, index) => Math.abs(value - b[index]) < 1e-10);
}

function isDimensionless(dimensions: Dimensions) {
	return dimensionsMatch(dimensions, DIMENSIONLESS);
}

function resolveUnit(rawUnit: string): Quantity {
	const direct = UNITS[rawUnit];
	if (direct) {
		return direct;
	}

	const alias = UNIT_ALIASES[rawUnit.toLowerCase()];
	if (alias && UNITS[alias]) {
		return UNITS[alias];
	}

	throw new Error(`Unknown unit: ${rawUnit}`);
}

function tokenize(input: string): Token[] {
	const tokens: Token[] = [];
	const tokenPattern =
		/\s*(?:(\d+(?:\.\d*)?|\.\d+)(?:[eE]([+-]?\d+))?|([A-Za-zµμ°]+)|([()+\-*/^]))/y;
	let offset = 0;

	while (offset < input.length) {
		tokenPattern.lastIndex = offset;
		const match = tokenPattern.exec(input);
		if (!match) {
			throw new Error(`Unexpected token at ${input.slice(offset)}`);
		}

		if (match[1]) {
			const exponent = match[2] ? Number.parseInt(match[2], 10) : 0;
			tokens.push({ type: "number", value: Number(match[1]) * 10 ** exponent });
		} else if (match[3]) {
			tokens.push({ type: "unit", value: match[3].replace(/[µμ]/g, "u") });
		} else if (match[4] === "(") {
			tokens.push({ type: "leftParen" });
		} else if (match[4] === ")") {
			tokens.push({ type: "rightParen" });
		} else {
			tokens.push({
				type: "operator",
				value: match[4] as "+" | "-" | "*" | "/" | "^",
			});
		}

		offset = tokenPattern.lastIndex;
	}

	const withImplicitMultiplication: Token[] = [];
	for (const token of tokens) {
		const previous =
			withImplicitMultiplication[withImplicitMultiplication.length - 1];
		const previousCanMultiply =
			previous?.type === "number" ||
			previous?.type === "unit" ||
			previous?.type === "rightParen";
		const currentCanMultiply =
			token.type === "number" ||
			token.type === "unit" ||
			token.type === "leftParen";

		if (previousCanMultiply && currentCanMultiply) {
			withImplicitMultiplication.push({
				type: "operator",
				value: "implicitMultiply",
			});
		}
		withImplicitMultiplication.push(token);
	}

	return withImplicitMultiplication;
}

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
					? result.value + right.value
					: result.value - right.value,
				result.dimensions,
			);
		}
		return result;
	}

	private parseMultiplicative(): Quantity {
		let result = this.parseImplicitMultiplicative();
		while (this.matchesOperator("*") || this.matchesOperator("/")) {
			const operator = (
				this.tokens[this.index] as Extract<Token, { type: "operator" }>
			).value;
			this.index += 1;
			const right = this.parseImplicitMultiplicative();
			result =
				operator === "*"
					? quantity(
							result.value * right.value,
							addDimensions(result.dimensions, right.dimensions),
						)
					: quantity(
							result.value / right.value,
							subtractDimensions(result.dimensions, right.dimensions),
						);
		}
		return result;
	}

	private parseImplicitMultiplicative(): Quantity {
		let result = this.parseUnary();
		while (this.matchesOperator("implicitMultiply")) {
			this.index += 1;
			const right = this.parseUnary();
			result = quantity(
				result.value * right.value,
				addDimensions(result.dimensions, right.dimensions),
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
			return quantity(-value.value, value.dimensions);
		}
		return this.parsePower();
	}

	private parsePower(): Quantity {
		const base = this.parsePrimary();
		if (!this.matchesOperator("^")) {
			return base;
		}

		this.index += 1;
		const exponent = this.parseUnary();
		if (!isDimensionless(exponent.dimensions)) {
			throw new Error("Unit exponents must be dimensionless");
		}

		return quantity(
			base.value ** exponent.value,
			scaleDimensions(base.dimensions, exponent.value),
		);
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

		if (token.type === "unit") {
			this.index += 1;
			return resolveUnit(token.value);
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
	return Number.isInteger(value) ? value.toString() : formatResult(value);
}

function formatBaseUnit(dimensions: Dimensions) {
	const names = ["kg", "m", "s", "A"];
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
	return denominator.length > 0 ? `${top}/${denominator.join("*")}` : top;
}

function inferTargetUnit(source: Quantity) {
	const group = AUTOMATIC_UNIT_GROUPS.find(({ dimensions }) =>
		dimensionsMatch(source.dimensions, dimensions),
	);
	if (!group) {
		return {
			unit: formatBaseUnit(source.dimensions),
			quantity: quantity(1, source.dimensions),
		};
	}

	if (source.value === 0) {
		return { unit: group.fallback, quantity: parseQuantity(group.fallback) };
	}

	for (const unit of group.units) {
		const target = parseQuantity(unit);
		const converted = Math.abs(source.value / target.value);
		if (converted >= 1 && converted < 1_000) {
			return { unit, quantity: target };
		}
	}

	const edgeUnit =
		Math.abs(source.value / parseQuantity(group.units[0]).value) >= 1_000
			? group.units[0]
			: group.units[group.units.length - 1];
	return { unit: edgeUnit, quantity: parseQuantity(edgeUnit) };
}

function formatResult(value: number) {
	if (!Number.isFinite(value)) {
		return value.toString();
	}

	const absoluteValue = Math.abs(value);
	if (absoluteValue !== 0 && (absoluteValue >= 1e12 || absoluteValue < 1e-9)) {
		return value.toExponential(8).replace(/\.0+(?=e)/, "");
	}

	return Number.parseFloat(value.toPrecision(12)).toString();
}

export function evaluateUnitExpression(
	query: string,
): UnitExpressionResult | null {
	const normalized = normalizeExpression(query);
	const inIndex = normalized.toLowerCase().lastIndexOf(" in ");
	const toIndex = normalized.toLowerCase().lastIndexOf(" to ");
	const separatorIndex = Math.max(inIndex, toIndex);
	const hasExplicitTarget = separatorIndex > 0;
	const expression = hasExplicitTarget
		? normalized.slice(0, separatorIndex).trim()
		: normalized;
	const targetUnit = hasExplicitTarget
		? normalized.slice(separatorIndex + 4).trim()
		: "";
	if (!expression || (hasExplicitTarget && !targetUnit)) return null;

	try {
		const source = parseQuantity(expression);
		if (!hasExplicitTarget && isDimensionless(source.dimensions)) return null;
		const inferredTarget = hasExplicitTarget ? null : inferTargetUnit(source);
		const resolvedTargetUnit = inferredTarget?.unit ?? targetUnit;
		const target = inferredTarget?.quantity ?? parseQuantity(targetUnit);
		if (
			!dimensionsMatch(source.dimensions, target.dimensions) ||
			target.value === 0
		) {
			return null;
		}

		const value = source.value / target.value;
		return {
			expression,
			targetUnit: resolvedTargetUnit,
			value,
			formattedValue: formatResult(value),
		};
	} catch {
		return null;
	}
}
