import {
	formatOpenAIRate,
	formatOpenAIUSD,
	OPENAI_PRICING_SOURCE_URL,
	OPENAI_PRICING_VERSION,
	resolveOpenAIModelPrice,
	type OpenAIStandardTextPrice,
} from "lib/openaiPricing";
import { isOfficialOpenAIAPIBaseURL } from "lib/aiHttp";
import { observer } from "mobx-react-lite";
import { Linking, Text, TouchableOpacity, View } from "react-native";
import { useStore } from "store";

function formatTokenCount(value: number) {
	if (value >= 1_000_000) {
		return `${Number.parseFloat((value / 1_000_000).toFixed(2))}M`;
	}
	if (value >= 1_000) {
		return `${Number.parseFloat((value / 1_000).toFixed(1))}K`;
	}
	return value.toString();
}

function formatModelRates(model: string, price: OpenAIStandardTextPrice) {
	const rates = [
		`$${formatOpenAIRate(price.inputUSDPerMillion)} input`,
		...(price.cachedInputUSDPerMillion == null
			? []
			: [`$${formatOpenAIRate(price.cachedInputUSDPerMillion)} cached`]),
		...(price.cacheWriteUSDPerMillion == null
			? []
			: [`$${formatOpenAIRate(price.cacheWriteUSDPerMillion)} cache write`]),
		`$${formatOpenAIRate(price.outputUSDPerMillion)} output`,
	];
	return `${model} catalog · ${rates.join(" · ")} / 1M tokens`;
}

export const OpenAICostSummary = observer(() => {
	const { ai } = useStore();
	const lifetime = ai.openAILifetimeCost;
	const selectedModel = ai.settings.openai.model.trim();
	const selectedPrice = resolveOpenAIModelPrice(selectedModel);
	const usesDirectOpenAI = isOfficialOpenAIAPIBaseURL(
		ai.settings.openai.baseURL,
	);
	const hasUnpricedRequests = lifetime.unpricedRequests > 0;
	const hasPartialRequests = lifetime.partialRequests > 0;
	const isSubtotal = hasUnpricedRequests || hasPartialRequests;

	return (
		<View className="rounded-lg border border-color subBg p-2.5 gap-1.5">
			<View className="flex-row items-start gap-2">
				<View className="flex-1">
					<Text className="text-[10px] font-semibold darker-text">
						OPENAI VIA SOL · LIFETIME ESTIMATE
					</Text>
					<Text className="text-lg font-semibold text">
						{isSubtotal ? "≥" : "≈"}
						{formatOpenAIUSD(lifetime.pricedSubtotalUSD)}
					</Text>
				</View>
				<Text className="text-xs darker-text text-right">
					{lifetime.requests} requests{"\n"}
					{formatTokenCount(lifetime.inputTokens)} in ·{" "}
					{formatTokenCount(lifetime.outputTokens)} out
				</Text>
			</View>

			{selectedPrice.priced ? (
				<>
					<Text className="text-xs darker-text">
						{formatModelRates(selectedModel, selectedPrice.price)}
					</Text>
					{selectedPrice.price.longContext && (
						<Text className="text-xs darker-text">
							Above {formatTokenCount(
								selectedPrice.price.longContext
									.inputTokenThresholdExclusive,
							)} input tokens: input ×
							{selectedPrice.price.longContext.inputMultiplier}, output ×
							{selectedPrice.price.longContext.outputMultiplier}.
						</Text>
					)}
				</>
			) : (
				<Text className="text-xs text-amber-600 dark:text-amber-400">
					{`${selectedModel || "Current model"}: price unavailable; its calls will be marked unpriced`}
				</Text>
			)}
			{!usesDirectOpenAI && (
				<Text className="text-xs text-amber-600 dark:text-amber-400">
					Custom OpenAI-compatible endpoint: requests are tracked as unpriced
					instead of applying OpenAI direct prices.
				</Text>
			)}

			{hasUnpricedRequests && (
				<Text className="text-xs text-amber-600 dark:text-amber-400">
					{`Subtotal only: ${lifetime.unpricedRequests} request${
						lifetime.unpricedRequests === 1 ? " was" : "s were"
					} excluded because no reliable price was available.`}
				</Text>
			)}
			{hasPartialRequests && (
				<Text className="text-xs text-amber-600 dark:text-amber-400">
					{`${lifetime.partialRequests} request${
						lifetime.partialRequests === 1 ? " has" : "s have"
					} known token costs plus possible additional charges.`}
				</Text>
			)}

			<View className="flex-row items-center gap-2">
				<Text className="flex-1 text-xs darker-text">
					Saved locally with no automatic reset. Standard token pricing only; tool
					charges and account adjustments are excluded.
				</Text>
				<TouchableOpacity
					className="px-1.5 py-0.5"
					onPress={() => void Linking.openURL(OPENAI_PRICING_SOURCE_URL)}
				>
					<Text className="text-xs text-accent">
						Rates as of {OPENAI_PRICING_VERSION}
					</Text>
				</TouchableOpacity>
			</View>
		</View>
	);
});
