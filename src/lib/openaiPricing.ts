/**
 * Standard OpenAI text-token prices captured from the official pricing page on
 * 2026-07-19. Prices are USD per 1M tokens and deliberately do not include
 * Batch, Flex, Priority, regional-processing uplifts, or tool-call charges.
 *
 * Source: https://developers.openai.com/api/docs/pricing
 */

export const OPENAI_PRICING_VERSION = "2026-07-19" as const;
export const OPENAI_PRICING_SOURCE_URL =
	"https://developers.openai.com/api/docs/pricing" as const;
export const OPENAI_PRICE_TOKEN_UNIT = 1_000_000 as const;

export function formatOpenAIUSD(value: number) {
	if (!Number.isFinite(value) || value < 0) return "$—";
	if (value === 0) return "$0.00";
	if (value < 0.000_001) return `$${value.toExponential(2)}`;
	if (value < 0.001) return `$${value.toFixed(6)}`;
	if (value < 1) return `$${value.toFixed(4)}`;
	return `$${value.toFixed(2)}`;
}

export function formatOpenAIRate(value: number) {
	return value.toString();
}

export type OpenAITextModelCategory =
	| "general"
	| "chat"
	| "codex"
	| "specialized";

export type OpenAILongContextPricing = {
	inputTokenThresholdExclusive: number;
	inputMultiplier: number;
	outputMultiplier: number;
};

export type OpenAIStandardTextPrice = {
	inputUSDPerMillion: number;
	cachedInputUSDPerMillion: number | null;
	cacheWriteUSDPerMillion: number | null;
	outputUSDPerMillion: number;
	category: OpenAITextModelCategory;
	longContext?: OpenAILongContextPricing;
	additionalChargesMayApply?: boolean;
};

const LONG_CONTEXT_OVER_272K: OpenAILongContextPricing = Object.freeze({
	inputTokenThresholdExclusive: 272_000,
	inputMultiplier: 2,
	outputMultiplier: 1.5,
});

function price(
	inputUSDPerMillion: number,
	cachedInputUSDPerMillion: number | null,
	outputUSDPerMillion: number,
	options: {
		cacheWriteUSDPerMillion?: number | null;
		category?: OpenAITextModelCategory;
		longContext?: OpenAILongContextPricing;
		additionalChargesMayApply?: boolean;
	} = {},
): OpenAIStandardTextPrice {
	return Object.freeze({
		inputUSDPerMillion,
		cachedInputUSDPerMillion,
		cacheWriteUSDPerMillion: options.cacheWriteUSDPerMillion ?? null,
		outputUSDPerMillion,
		category: options.category ?? "general",
		...(options.longContext ? { longContext: options.longContext } : {}),
		...(options.additionalChargesMayApply
			? { additionalChargesMayApply: true }
			: {}),
	});
}

/**
 * General text-and-code rows plus the token-priced text-output rows from the
 * specialized ChatGPT, Codex, Cyber, Search, Deep research, and Computer use
 * sections. A null rate means the official table does not publish that token
 * category for the model; it never means that the category is free.
 */
export const OPENAI_STANDARD_TEXT_PRICES_2026_07_19: Readonly<
	Record<string, OpenAIStandardTextPrice>
> = Object.freeze({
	"gpt-5.6-sol": price(5, 0.5, 30, {
		cacheWriteUSDPerMillion: 6.25,
		longContext: LONG_CONTEXT_OVER_272K,
	}),
	"gpt-5.6-terra": price(2.5, 0.25, 15, {
		cacheWriteUSDPerMillion: 3.125,
		longContext: LONG_CONTEXT_OVER_272K,
	}),
	"gpt-5.6-luna": price(1, 0.1, 6, {
		cacheWriteUSDPerMillion: 1.25,
		longContext: LONG_CONTEXT_OVER_272K,
	}),
	"gpt-5.5": price(5, 0.5, 30, {
		longContext: LONG_CONTEXT_OVER_272K,
	}),
	"gpt-5.5-pro": price(30, null, 180, {
		longContext: LONG_CONTEXT_OVER_272K,
	}),
	"gpt-5.4": price(2.5, 0.25, 15, {
		longContext: LONG_CONTEXT_OVER_272K,
	}),
	"gpt-5.4-mini": price(0.75, 0.075, 4.5),
	"gpt-5.4-nano": price(0.2, 0.02, 1.25),
	"gpt-5.4-pro": price(30, null, 180, {
		longContext: LONG_CONTEXT_OVER_272K,
	}),
	"gpt-5.2": price(1.75, 0.175, 14),
	"gpt-5.2-pro": price(21, null, 168),
	"gpt-5.1": price(1.25, 0.125, 10),
	"gpt-5": price(1.25, 0.125, 10),
	"gpt-5-mini": price(0.25, 0.025, 2),
	"gpt-5-nano": price(0.05, 0.005, 0.4),
	"gpt-5-pro": price(15, null, 120),
	"gpt-4.1": price(2, 0.5, 8),
	"gpt-4.1-mini": price(0.4, 0.1, 1.6),
	"gpt-4.1-nano": price(0.1, 0.025, 0.4),
	"gpt-4o": price(2.5, 1.25, 10),
	"gpt-4o-2024-05-13": price(5, null, 15),
	"gpt-4o-mini": price(0.15, 0.075, 0.6),
	o1: price(15, 7.5, 60),
	"o1-pro": price(150, null, 600),
	"o3-pro": price(20, null, 80),
	o3: price(2, 0.5, 8),
	"o4-mini": price(1.1, 0.275, 4.4),
	"o3-mini": price(1.1, 0.55, 4.4),
	"o1-mini": price(1.1, 0.55, 4.4),
	"gpt-4-turbo-2024-04-09": price(10, null, 30),
	"gpt-4-0125-preview": price(10, null, 30),
	"gpt-4-1106-preview": price(10, null, 30),
	"gpt-4-1106-vision-preview": price(10, null, 30),
	"gpt-4-0613": price(30, null, 60),
	"gpt-4-0314": price(30, null, 60),
	"gpt-4-32k": price(60, null, 120),
	"gpt-3.5-turbo": price(0.5, null, 1.5),
	"gpt-3.5-turbo-0125": price(0.5, null, 1.5),
	"gpt-3.5-turbo-1106": price(1, null, 2),
	"gpt-3.5-turbo-0613": price(1.5, null, 2),
	"gpt-3.5-0301": price(1.5, null, 2),
	"gpt-3.5-turbo-instruct": price(1.5, null, 2),
	"gpt-3.5-turbo-16k-0613": price(3, null, 4),
	"davinci-002": price(2, null, 2),
	"babbage-002": price(0.4, null, 0.4),

	"chat-latest": price(5, 0.5, 30, { category: "chat" }),
	"gpt-5.3-chat-latest": price(1.75, 0.175, 14, {
		category: "chat",
	}),
	"gpt-5.2-chat-latest": price(1.75, 0.175, 14, {
		category: "chat",
	}),
	"gpt-5.1-chat-latest": price(1.25, 0.125, 10, {
		category: "chat",
	}),
	"gpt-5-chat-latest": price(1.25, 0.125, 10, { category: "chat" }),
	"chatgpt-4o-latest": price(5, null, 15, { category: "chat" }),

	"gpt-5.3-codex": price(1.75, 0.175, 14, { category: "codex" }),
	"gpt-5.2-codex": price(1.75, 0.175, 14, { category: "codex" }),
	"gpt-5.1-codex-max": price(1.25, 0.125, 10, { category: "codex" }),
	"gpt-5.1-codex": price(1.25, 0.125, 10, { category: "codex" }),
	"gpt-5-codex": price(1.25, 0.125, 10, { category: "codex" }),
	"gpt-5.1-codex-mini": price(0.25, 0.025, 2, { category: "codex" }),
	"codex-mini-latest": price(1.5, 0.375, 6, { category: "codex" }),

	"gpt-5.5-cyber": price(12.5, 1.25, 75, { category: "specialized" }),
	"gpt-5-search-api": price(1.25, 0.125, 10, {
		category: "specialized",
		additionalChargesMayApply: true,
	}),
	"gpt-4o-search-preview": price(2.5, null, 10, {
		category: "specialized",
		additionalChargesMayApply: true,
	}),
	"gpt-4o-mini-search-preview": price(0.15, null, 0.6, {
		category: "specialized",
		additionalChargesMayApply: true,
	}),
	"o3-deep-research": price(10, 2.5, 40, {
		category: "specialized",
		additionalChargesMayApply: true,
	}),
	"o4-mini-deep-research": price(2, 0.5, 8, {
		category: "specialized",
		additionalChargesMayApply: true,
	}),
	"computer-use-preview": price(3, null, 12, {
		category: "specialized",
		additionalChargesMayApply: true,
	}),
});

export const OPENAI_STANDARD_TEXT_PRICES =
	OPENAI_STANDARD_TEXT_PRICES_2026_07_19;

/** Models present on the official pricing page without a published token price. */
export const OPENAI_LISTED_BUT_UNPRICED_TEXT_MODELS = Object.freeze([
	"gpt-5.4-cyber",
] as const);

const LISTED_BUT_UNPRICED = new Set<string>(
	OPENAI_LISTED_BUT_UNPRICED_TEXT_MODELS,
);

const EXACT_MODEL_ALIASES: Readonly<Record<string, string>> = Object.freeze({
	"gpt-5.6": "gpt-5.6-sol",
	"gpt-4-turbo": "gpt-4-turbo-2024-04-09",
	"gpt-4-turbo-preview": "gpt-4-0125-preview",
	"gpt-4": "gpt-4-0613",
	"gpt-4-32k-0613": "gpt-4-32k",
	"gpt-3.5-turbo-0301": "gpt-3.5-0301",
	"gpt-3.5-turbo-16k": "gpt-3.5-turbo-16k-0613",
});

/**
 * Families whose dated snapshots use the same price as their base model. The
 * resolver only accepts a strict YYYY-MM-DD suffix dated no later than this
 * table's version, so an unknown future snapshot is never priced by accident.
 */
const SNAPSHOT_FAMILIES = new Set<string>([
	"gpt-5.6-sol",
	"gpt-5.6-terra",
	"gpt-5.6-luna",
	"gpt-5.5",
	"gpt-5.5-pro",
	"gpt-5.4",
	"gpt-5.4-mini",
	"gpt-5.4-nano",
	"gpt-5.4-pro",
	"gpt-5.2",
	"gpt-5.2-pro",
	"gpt-5.1",
	"gpt-5",
	"gpt-5-mini",
	"gpt-5-nano",
	"gpt-5-pro",
	"gpt-4.1",
	"gpt-4.1-mini",
	"gpt-4.1-nano",
	"gpt-4o",
	"gpt-4o-mini",
	"o1",
	"o1-pro",
	"o3",
	"o3-pro",
	"o4-mini",
	"o3-mini",
	"o1-mini",
	"gpt-5.3-codex",
	"gpt-5.2-codex",
	"gpt-5.1-codex-max",
	"gpt-5.1-codex",
	"gpt-5-codex",
	"gpt-5.1-codex-mini",
]);

export type OpenAIPriceMatch = "exact" | "alias" | "snapshot";

export type ResolvedOpenAIModelPrice = {
	priced: true;
	requestedModel: string;
	pricedAsModel: string;
	match: OpenAIPriceMatch;
	price: OpenAIStandardTextPrice;
};

export type UnpricedOpenAIModel = {
	priced: false;
	requestedModel: string;
	reason:
		| "empty-model"
		| "fine-tuned-model"
		| "listed-without-price"
		| "unknown-model";
};

export type OpenAIModelPriceResolution =
	| ResolvedOpenAIModelPrice
	| UnpricedOpenAIModel;

function hasOwnPrice(model: string) {
	return Object.prototype.hasOwnProperty.call(OPENAI_STANDARD_TEXT_PRICES, model);
}

function isValidSnapshotDate(value: string) {
	const match = /^(\d{4})-(\d{2})-(\d{2})$/.exec(value);
	if (!match) return false;
	const year = Number(match[1]);
	const month = Number(match[2]);
	const day = Number(match[3]);
	const date = new Date(Date.UTC(year, month - 1, day));
	return (
		date.getUTCFullYear() === year &&
		date.getUTCMonth() === month - 1 &&
		date.getUTCDate() === day
	);
}

function snapshotFamily(model: string) {
	const match = /^(.*)-(\d{4}-\d{2}-\d{2})$/.exec(model);
	if (!match) return null;
	const family = match[1];
	const snapshotDate = match[2];
	if (
		!SNAPSHOT_FAMILIES.has(family) ||
		!isValidSnapshotDate(snapshotDate) ||
		snapshotDate > OPENAI_PRICING_VERSION ||
		!hasOwnPrice(family)
	) {
		return null;
	}
	return family;
}

export function resolveOpenAIModelPrice(model: string): OpenAIModelPriceResolution {
	const requestedModel = model.trim();
	if (!requestedModel) {
		return { priced: false, requestedModel, reason: "empty-model" };
	}
	if (requestedModel.startsWith("ft:")) {
		return { priced: false, requestedModel, reason: "fine-tuned-model" };
	}
	if (hasOwnPrice(requestedModel)) {
		return {
			priced: true,
			requestedModel,
			pricedAsModel: requestedModel,
			match: "exact",
			price: OPENAI_STANDARD_TEXT_PRICES[requestedModel],
		};
	}
	if (LISTED_BUT_UNPRICED.has(requestedModel)) {
		return {
			priced: false,
			requestedModel,
			reason: "listed-without-price",
		};
	}

	const alias = EXACT_MODEL_ALIASES[requestedModel];
	if (alias && hasOwnPrice(alias)) {
		return {
			priced: true,
			requestedModel,
			pricedAsModel: alias,
			match: "alias",
			price: OPENAI_STANDARD_TEXT_PRICES[alias],
		};
	}

	const family = snapshotFamily(requestedModel);
	if (family) {
		return {
			priced: true,
			requestedModel,
			pricedAsModel: family,
			match: "snapshot",
			price: OPENAI_STANDARD_TEXT_PRICES[family],
		};
	}

	return { priced: false, requestedModel, reason: "unknown-model" };
}

/**
 * Normalized Responses API usage. `inputTokens` is the total input count and
 * therefore includes the cached and cache-write subsets. Prefer the model ID
 * returned by the API over the requested alias when it is available.
 */
export type OpenAITokenUsage = {
	model: string;
	inputTokens: number;
	outputTokens: number;
	cachedInputTokens?: number;
	cacheWriteTokens?: number;
};

export type NormalizedOpenAITokenUsage = {
	model: string;
	inputTokens: number;
	uncachedInputTokens: number;
	cachedInputTokens: number;
	cacheWriteTokens: number;
	outputTokens: number;
};

export type OpenAICostBreakdownUSD = {
	uncachedInput: number;
	cachedInput: number;
	cacheWrite: number;
	output: number;
};

export type PricedOpenAIUsage = {
	priced: true;
	costUSD: number;
	breakdownUSD: OpenAICostBreakdownUSD;
	usage: NormalizedOpenAITokenUsage;
	modelPrice: ResolvedOpenAIModelPrice;
	longContextApplied: boolean;
	additionalChargesMayApply: boolean;
};

export type UnpricedOpenAIUsageReason =
	| UnpricedOpenAIModel["reason"]
	| "invalid-usage"
	| "usage-unavailable"
	| "non-official-endpoint"
	| "non-standard-service-tier"
	| "cached-input-price-unavailable"
	| "cache-write-price-unavailable";

export type UnpricedOpenAIUsage = {
	priced: false;
	costUSD: null;
	reason: UnpricedOpenAIUsageReason;
	usage: NormalizedOpenAITokenUsage | null;
	modelPrice: OpenAIModelPriceResolution | null;
};

export type OpenAIUsageCostEstimate = PricedOpenAIUsage | UnpricedOpenAIUsage;

function isValidTokenCount(value: number) {
	return Number.isSafeInteger(value) && value >= 0;
}

function normalizeUsage(
	usage: OpenAITokenUsage,
): NormalizedOpenAITokenUsage | null {
	const model = usage.model.trim();
	const cachedInputTokens = usage.cachedInputTokens ?? 0;
	const cacheWriteTokens = usage.cacheWriteTokens ?? 0;
	if (
		!isValidTokenCount(usage.inputTokens) ||
		!isValidTokenCount(usage.outputTokens) ||
		!isValidTokenCount(cachedInputTokens) ||
		!isValidTokenCount(cacheWriteTokens) ||
		cachedInputTokens + cacheWriteTokens > usage.inputTokens
	) {
		return null;
	}
	return {
		model,
		inputTokens: usage.inputTokens,
		uncachedInputTokens:
			usage.inputTokens - cachedInputTokens - cacheWriteTokens,
		cachedInputTokens,
		cacheWriteTokens,
		outputTokens: usage.outputTokens,
	};
}

export function estimateOpenAIUsageCost(
	usage: OpenAITokenUsage,
): OpenAIUsageCostEstimate {
	const normalized = normalizeUsage(usage);
	if (!normalized) {
		return {
			priced: false,
			costUSD: null,
			reason: "invalid-usage",
			usage: null,
			modelPrice: null,
		};
	}

	const modelPrice = resolveOpenAIModelPrice(normalized.model);
	if (!modelPrice.priced) {
		return {
			priced: false,
			costUSD: null,
			reason: modelPrice.reason,
			usage: normalized,
			modelPrice,
		};
	}

	const rate = modelPrice.price;
	if (normalized.cachedInputTokens > 0 && rate.cachedInputUSDPerMillion === null) {
		return {
			priced: false,
			costUSD: null,
			reason: "cached-input-price-unavailable",
			usage: normalized,
			modelPrice,
		};
	}
	if (normalized.cacheWriteTokens > 0 && rate.cacheWriteUSDPerMillion === null) {
		return {
			priced: false,
			costUSD: null,
			reason: "cache-write-price-unavailable",
			usage: normalized,
			modelPrice,
		};
	}

	const longContextApplied = Boolean(
		rate.longContext &&
			normalized.inputTokens > rate.longContext.inputTokenThresholdExclusive,
	);
	const inputMultiplier = longContextApplied
		? rate.longContext?.inputMultiplier ?? 1
		: 1;
	const outputMultiplier = longContextApplied
		? rate.longContext?.outputMultiplier ?? 1
		: 1;
	const perToken = 1 / OPENAI_PRICE_TOKEN_UNIT;
	const breakdownUSD: OpenAICostBreakdownUSD = {
		uncachedInput:
			normalized.uncachedInputTokens *
			rate.inputUSDPerMillion *
			inputMultiplier *
			perToken,
		cachedInput:
			normalized.cachedInputTokens *
			(rate.cachedInputUSDPerMillion ?? 0) *
			inputMultiplier *
			perToken,
		cacheWrite:
			normalized.cacheWriteTokens *
			(rate.cacheWriteUSDPerMillion ?? 0) *
			inputMultiplier *
			perToken,
		output:
			normalized.outputTokens *
			rate.outputUSDPerMillion *
			outputMultiplier *
			perToken,
	};

	return {
		priced: true,
		costUSD:
			breakdownUSD.uncachedInput +
			breakdownUSD.cachedInput +
			breakdownUSD.cacheWrite +
			breakdownUSD.output,
		breakdownUSD,
		usage: normalized,
		modelPrice,
		longContextApplied,
		additionalChargesMayApply: rate.additionalChargesMayApply ?? false,
	};
}

export type OpenAILifetimeModelCost = {
	requests: number;
	pricedRequests: number;
	unpricedRequests: number;
	partialRequests: number;
	pricedSubtotalUSD: number;
	inputTokens: number;
	cachedInputTokens: number;
	cacheWriteTokens: number;
	outputTokens: number;
};

export type OpenAILifetimeCost = OpenAILifetimeModelCost & {
	schemaVersion: 1;
	lastPricingVersion: string;
	currency: "USD";
	byModel: Record<string, OpenAILifetimeModelCost>;
};

const EMPTY_MODEL_COST: OpenAILifetimeModelCost = Object.freeze({
	requests: 0,
	pricedRequests: 0,
	unpricedRequests: 0,
	partialRequests: 0,
	pricedSubtotalUSD: 0,
	inputTokens: 0,
	cachedInputTokens: 0,
	cacheWriteTokens: 0,
	outputTokens: 0,
});

export function createEmptyOpenAILifetimeCost(): OpenAILifetimeCost {
	return {
		schemaVersion: 1,
		lastPricingVersion: OPENAI_PRICING_VERSION,
		currency: "USD",
		...EMPTY_MODEL_COST,
		byModel: {},
	};
}

function asRecord(value: unknown): Record<string, unknown> | null {
	return typeof value === "object" && value !== null
		? (value as Record<string, unknown>)
		: null;
}

function persistedCount(value: unknown) {
	return typeof value === "number" && Number.isSafeInteger(value) && value >= 0
		? value
		: 0;
}

function persistedUSD(value: unknown) {
	return typeof value === "number" && Number.isFinite(value) && value >= 0
		? value
		: 0;
}

function restoreModelCost(value: unknown): OpenAILifetimeModelCost {
	const record = asRecord(value);
	if (!record) return { ...EMPTY_MODEL_COST };
	const requests = persistedCount(record.requests);
	const pricedRequests = Math.min(
		requests,
		persistedCount(record.pricedRequests),
	);
	const unpricedRequests = Math.min(
		requests,
		persistedCount(record.unpricedRequests),
	);
	const normalizedRequests = Math.max(
		requests,
		pricedRequests + unpricedRequests,
	);
	return {
		requests: normalizedRequests,
		pricedRequests,
		unpricedRequests: normalizedRequests - pricedRequests,
		partialRequests: Math.min(
			pricedRequests,
			persistedCount(record.partialRequests),
		),
		pricedSubtotalUSD: persistedUSD(record.pricedSubtotalUSD),
		inputTokens: persistedCount(record.inputTokens),
		cachedInputTokens: persistedCount(record.cachedInputTokens),
		cacheWriteTokens: persistedCount(record.cacheWriteTokens),
		outputTokens: persistedCount(record.outputTokens),
	};
}

export function restoreOpenAILifetimeCost(value: unknown): OpenAILifetimeCost {
	const record = asRecord(value);
	if (!record) return createEmptyOpenAILifetimeCost();
	const byModelRecord = asRecord(record.byModel);
	const byModel: Record<string, OpenAILifetimeModelCost> = {};
	if (byModelRecord) {
		for (const [model, modelCost] of Object.entries(byModelRecord)) {
			if (model.trim()) byModel[model] = restoreModelCost(modelCost);
		}
	}
	return {
		schemaVersion: 1,
		lastPricingVersion:
			typeof record.lastPricingVersion === "string"
				? record.lastPricingVersion
				: typeof record.pricingVersion === "string"
					? record.pricingVersion
					: OPENAI_PRICING_VERSION,
		currency: "USD",
		...restoreModelCost(record),
		byModel,
	};
}

function addEstimateToCost(
	current: OpenAILifetimeModelCost,
	estimate: OpenAIUsageCostEstimate,
): OpenAILifetimeModelCost {
	const usage = estimate.usage;
	return {
		requests: current.requests + 1,
		pricedRequests: current.pricedRequests + (estimate.priced ? 1 : 0),
		unpricedRequests: current.unpricedRequests + (estimate.priced ? 0 : 1),
		partialRequests:
			current.partialRequests +
			(estimate.priced && estimate.additionalChargesMayApply ? 1 : 0),
		pricedSubtotalUSD:
			current.pricedSubtotalUSD + (estimate.priced ? estimate.costUSD : 0),
		inputTokens: current.inputTokens + (usage?.inputTokens ?? 0),
		cachedInputTokens:
			current.cachedInputTokens + (usage?.cachedInputTokens ?? 0),
		cacheWriteTokens:
			current.cacheWriteTokens + (usage?.cacheWriteTokens ?? 0),
		outputTokens: current.outputTokens + (usage?.outputTokens ?? 0),
	};
}

/**
 * Adds one request without mutating the previous state. `pricedSubtotalUSD` is
 * intentionally named a subtotal: if `unpricedRequests` is non-zero, it is not
 * the account's complete cost and must not be presented as one.
 */
export function accumulateOpenAIUsageCost(
	current: OpenAILifetimeCost,
	usage: OpenAITokenUsage,
): { lifetime: OpenAILifetimeCost; estimate: OpenAIUsageCostEstimate } {
	const estimate = estimateOpenAIUsageCost(usage);
	return accumulateEstimate(current, usage.model, estimate);
}

function accumulateEstimate(
	current: OpenAILifetimeCost,
	model: string,
	estimate: OpenAIUsageCostEstimate,
): { lifetime: OpenAILifetimeCost; estimate: OpenAIUsageCostEstimate } {
	const modelKey = model.trim() || "(missing model)";
	const previousModel = current.byModel[modelKey] ?? EMPTY_MODEL_COST;
	return {
		estimate,
		lifetime: {
			...current,
			...addEstimateToCost(current, estimate),
			lastPricingVersion: OPENAI_PRICING_VERSION,
			byModel: {
				...current.byModel,
				[modelKey]: addEstimateToCost(previousModel, estimate),
			},
		},
	};
}

export function accumulateUnpricedOpenAIUsage(
	current: OpenAILifetimeCost,
	usage: OpenAITokenUsage,
	reason: "non-official-endpoint" | "non-standard-service-tier",
) {
	const normalized = normalizeUsage(usage);
	const estimate: UnpricedOpenAIUsage = normalized
		? {
				priced: false,
				costUSD: null,
				reason,
				usage: normalized,
				modelPrice: resolveOpenAIModelPrice(normalized.model),
			}
		: {
				priced: false,
				costUSD: null,
				reason: "invalid-usage",
				usage: null,
				modelPrice: null,
			};
	return accumulateEstimate(current, usage.model, estimate);
}

export function accumulateOpenAIRequestWithoutUsage(
	current: OpenAILifetimeCost,
	model: string,
) {
	const requestedModel = model.trim();
	const estimate: UnpricedOpenAIUsage = {
		priced: false,
		costUSD: null,
		reason: "usage-unavailable",
		usage: null,
		modelPrice: requestedModel
			? resolveOpenAIModelPrice(requestedModel)
			: null,
	};
	return accumulateEstimate(current, requestedModel, estimate);
}
