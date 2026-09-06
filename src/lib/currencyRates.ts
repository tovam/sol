import axios from "axios";

export const CURRENCY_RATE_SOURCE_NAME = "Coinbase";
export const CURRENCY_RATE_SOURCE_URL =
	"https://api.coinbase.com/v2/exchange-rates?currency=EUR";
export const DEFAULT_CURRENCY_REFRESH_INTERVAL_MINUTES = 10;
export const MIN_CURRENCY_REFRESH_INTERVAL_MINUTES = 1;
export const MAX_CURRENCY_REFRESH_INTERVAL_MINUTES = 1_440;

export const CURRENCY_CODES = ["EUR", "USD", "BTC"] as const;

export type CurrencyCode = (typeof CURRENCY_CODES)[number];

export type CurrencyRateSnapshot = {
	base: "EUR";
	rates: Record<CurrencyCode, string>;
	fetchedAt: number;
	source: typeof CURRENCY_RATE_SOURCE_NAME;
};

type CoinbaseExchangeRatesResponse = {
	data?: {
		currency?: unknown;
		rates?: Record<string, unknown>;
	};
};

const isPositiveDecimal = (value: unknown): value is string => {
	if (typeof value !== "string" || value.trim() === "") return false;
	const parsed = Number(value);
	return Number.isFinite(parsed) && parsed > 0;
};

export const currencyCodeForIdentifier = (
	identifier: string,
): CurrencyCode | null => {
	if (identifier === "$") return "USD";
	if (identifier === "€") return "EUR";
	const normalized = identifier.toUpperCase();
	return CURRENCY_CODES.includes(normalized as CurrencyCode)
		? (normalized as CurrencyCode)
		: null;
};

export function normalizeCurrencyRateSnapshot(
	value: unknown,
): CurrencyRateSnapshot | null {
	if (value == null || typeof value !== "object") return null;
	const candidate = value as Partial<CurrencyRateSnapshot>;
	if (
		candidate.base !== "EUR" ||
		candidate.source !== CURRENCY_RATE_SOURCE_NAME ||
		typeof candidate.fetchedAt !== "number" ||
		!Number.isFinite(candidate.fetchedAt) ||
		candidate.fetchedAt <= 0 ||
		candidate.rates == null ||
		!isPositiveDecimal(candidate.rates.EUR) ||
		!isPositiveDecimal(candidate.rates.USD) ||
		!isPositiveDecimal(candidate.rates.BTC)
	) {
		return null;
	}

	return {
		base: "EUR",
		rates: {
			EUR: candidate.rates.EUR,
			USD: candidate.rates.USD,
			BTC: candidate.rates.BTC,
		},
		fetchedAt: candidate.fetchedAt,
		source: CURRENCY_RATE_SOURCE_NAME,
	};
}

export function parseCoinbaseCurrencyRates(
	response: CoinbaseExchangeRatesResponse,
	fetchedAt = Date.now(),
): CurrencyRateSnapshot {
	const rates = response.data?.rates;
	if (
		response.data?.currency !== "EUR" ||
		rates == null ||
		!isPositiveDecimal(rates.EUR) ||
		!isPositiveDecimal(rates.USD) ||
		!isPositiveDecimal(rates.BTC)
	) {
		throw new Error("Coinbase returned invalid EUR, USD, or BTC rates");
	}

	return {
		base: "EUR",
		rates: {
			EUR: rates.EUR,
			USD: rates.USD,
			BTC: rates.BTC,
		},
		fetchedAt,
		source: CURRENCY_RATE_SOURCE_NAME,
	};
}

export async function fetchCurrencyRates(): Promise<CurrencyRateSnapshot> {
	const response = await axios.get<CoinbaseExchangeRatesResponse>(
		CURRENCY_RATE_SOURCE_URL,
		{
			timeout: 8_000,
			headers: { Accept: "application/json" },
		},
	);
	return parseCoinbaseCurrencyRates(response.data);
}
