import { Dropdown } from "components/Dropdown";
import type { AIProvider } from "lib/ai";
import { observer } from "mobx-react-lite";
import { useEffect } from "react";
import {
	ActivityIndicator,
	Text,
	TouchableOpacity,
	View,
} from "react-native";
import { useStore } from "store";

type Props = {
	compact?: boolean;
	disabled?: boolean;
	onSelectionChange?: () => void;
	showError?: boolean;
};

const PROVIDERS: Array<{ id: AIProvider; label: string }> = [
	{ id: "openai", label: "OpenAI" },
	{ id: "openwebui", label: "OpenWebUI" },
];

export const AIProviderModelControls = observer(
	({
		compact = false,
		disabled = false,
		onSelectionChange,
		showError = !compact,
	}: Props) => {
		const { ai } = useStore();
		const provider = ai.settings.provider;
		const current = ai.settings[provider];
		const loading = ai.modelsLoading[provider] || ai.secretsLoading;
		const controlsDisabled =
			disabled || ai.secretsLoading || !ai.initialized;
		const error =
			ai.modelsError[provider] ||
			ai.secretsError ||
			ai.initializationError;
		const canRefresh =
			!!current.baseURL.trim() &&
			(provider !== "openai" ||
				!!current.apiKey.trim() ||
				!!ai.secretsError);
		const modelOptions = ai.currentModelOptions.map((model) => ({
			value: model.id,
			label:
				model.name && model.name !== model.id
					? `${model.name} — ${model.id}`
					: model.id,
		}));

		useEffect(() => {
			if (ai.initialized) {
				void ai.refreshModels(provider);
			}
			// Refresh once when the controls appear and whenever the provider changes.
			// URL/key edits use the explicit refresh button to avoid a request per keypress.
			// eslint-disable-next-line react-hooks/exhaustive-deps
		}, [ai.initialized, provider]);

		const refresh = async () => {
			if (ai.secretsError && !current.apiKey.trim()) {
				await ai.ensureSecretsLoaded(true);
			}
			await ai.refreshModels(provider);
		};

		return (
			<View className={showError ? "gap-1" : undefined}>
				<View className="flex-row items-center gap-2">
					<View className="flex-row p-0.5 rounded-lg border border-color subBg">
						{PROVIDERS.map((option) => {
							const selected = provider === option.id;
							return (
								<TouchableOpacity
									key={option.id}
									disabled={controlsDisabled}
									className={`rounded-md ${compact ? "px-2 py-1" : "px-3 py-1.5"} ${
										selected ? "bg-accent-strong" : ""
									}`}
									onPress={() => {
										ai.setProvider(option.id);
										onSelectionChange?.();
									}}
								>
									<Text
										className={`${compact ? "text-xs" : "text-sm"} ${
											selected ? "text-white font-semibold" : "text"
										}`}
									>
										{option.label}
									</Text>
								</TouchableOpacity>
							);
						})}
					</View>

					<Dropdown
						value={current.model}
						options={modelOptions}
						onValueChange={(model) => {
							ai.setModel(provider, String(model));
							onSelectionChange?.();
						}}
						placeholder={loading ? "Loading models…" : "Choose a model"}
						disabled={controlsDisabled || loading || modelOptions.length === 0}
						className={compact ? "h-7" : "h-8"}
						style={{ width: compact ? 210 : 300 }}
					/>

					<TouchableOpacity
						disabled={controlsDisabled || loading || !canRefresh}
						className={`${compact ? "h-7 w-7" : "h-8 w-8"} rounded-lg border border-color subBg items-center justify-center ${
							controlsDisabled || !canRefresh ? "opacity-50" : ""
						}`}
						onPress={() => void refresh()}
					>
						{loading ? (
							<ActivityIndicator size="small" />
						) : (
							<Text className={error ? "text-red-500" : "text"}>↻</Text>
						)}
					</TouchableOpacity>
				</View>

				{showError && !!error && (
					<Text className="text-xs text-red-500" numberOfLines={2}>
						{error}
					</Text>
				)}
			</View>
		);
	},
);
