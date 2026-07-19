import { BackButton } from "components/BackButton";
import { Key } from "components/Key";
import type { AIProvider } from "lib/ai";
import { solNative } from "lib/SolNative";
import { observer } from "mobx-react-lite";
import { useEffect, useRef, useState } from "react";
import {
	ActivityIndicator,
	ScrollView,
	Text,
	TouchableOpacity,
	View,
} from "react-native";
import { useStore } from "store";
import { Widget } from "stores/ui.store";

const PROVIDERS: AIProvider[] = ["openwebui", "openai"];
const PROVIDER_LABELS: Record<AIProvider, string> = {
	openwebui: "OpenWebUI",
	openai: "OpenAI",
};

type ModelChoice = {
	key: string;
	provider: AIProvider;
	model: string;
	name: string;
	disabled: boolean;
	loading: boolean;
};

export const AIModelPickerWidget = observer(() => {
	const store = useStore();
	const scrollView = useRef<ScrollView>(null);
	const choicesRef = useRef<ModelChoice[]>([]);
	const selectedIndexRef = useRef(0);
	const launchRef = useRef<() => void>(() => undefined);
	const mountedRef = useRef(true);
	const [selectedKey, setSelectedKey] = useState<string | null>(null);
	const [refreshingProviders, setRefreshingProviders] = useState<
		Record<AIProvider, boolean>
	>({ openwebui: true, openai: true });

	const refreshProvider = async (provider: AIProvider) => {
		if (mountedRef.current) {
			setRefreshingProviders((current) => ({ ...current, [provider]: true }));
		}
		try {
			await store.ai.refreshModels(provider);
		} finally {
			if (mountedRef.current) {
				setRefreshingProviders((current) => ({ ...current, [provider]: false }));
			}
		}
	};

	const refreshModels = async () => {
		await Promise.allSettled(
			PROVIDERS.map((provider) => refreshProvider(provider)),
		);
	};

	useEffect(() => {
		mountedRef.current = true;
		void refreshModels();
		return () => {
			mountedRef.current = false;
		};
		// The AI store is stable for the lifetime of this widget.
		// eslint-disable-next-line react-hooks/exhaustive-deps
	}, []);

	const choices = PROVIDERS.flatMap((provider): ModelChoice[] => {
		const configuredModel = store.ai.settings[provider].model.trim();
		const availableModels = store.ai.modelsByProvider[provider];
		const loading =
			refreshingProviders[provider] || store.ai.modelsLoading[provider];
		const seen = new Set<string>();
		const providerChoices: ModelChoice[] = [];

		if (availableModels.length === 0 && configuredModel) {
			seen.add(configuredModel);
			providerChoices.push({
				key: `${provider}:${configuredModel}`,
				provider,
				model: configuredModel,
				name: configuredModel,
				disabled: loading,
				loading,
			});
		}

		for (const model of availableModels) {
			if (seen.has(model.id)) continue;
			seen.add(model.id);
			providerChoices.push({
				key: `${provider}:${model.id}`,
				provider,
				model: model.id,
				name: model.name || model.id,
				disabled: loading,
				loading,
			});
		}

		if (providerChoices.length > 0) return providerChoices;
		return [
			{
				key: `${provider}:placeholder`,
				provider,
				model: "",
				name: loading
					? "Loading models…"
					: store.ai.modelsError[provider] || "No compatible model",
				disabled: true,
				loading,
			},
		];
	});

	const requestedIndex = selectedKey
		? choices.findIndex((choice) => choice.key === selectedKey)
		: -1;
	const defaultOpenWebUIIndex = choices.findIndex(
		(choice) => choice.provider === "openwebui" && !choice.disabled,
	);
	const firstOpenWebUIIndex = choices.findIndex(
		(choice) => choice.provider === "openwebui",
	);
	const selectedIndex =
		requestedIndex >= 0
			? requestedIndex
			: defaultOpenWebUIIndex >= 0
				? defaultOpenWebUIIndex
				: Math.max(0, firstOpenWebUIIndex);
	const selectedChoice = choices[selectedIndex];

	choicesRef.current = choices;
	selectedIndexRef.current = selectedIndex;

	const moveSelection = (direction: -1 | 1) => {
		const currentChoices = choicesRef.current;
		if (currentChoices.length === 0) return;
		let index = selectedIndexRef.current;
		for (let attempt = 0; attempt < currentChoices.length; attempt++) {
			index = (index + direction + currentChoices.length) % currentChoices.length;
			if (!currentChoices[index].disabled) {
				setSelectedKey(currentChoices[index].key);
				return;
			}
		}
	};

	const launchConversation = () => {
		if (!selectedChoice || selectedChoice.disabled || !selectedChoice.model) {
			return;
		}
		const prompt = store.ui.query.trim();
		if (!prompt) {
			store.ui.focusWidget(Widget.SEARCH);
			return;
		}

		store.ai.setProvider(selectedChoice.provider);
		store.ai.setModel(selectedChoice.provider, selectedChoice.model);
		store.ai.startNewConversation();
		store.ai.queueConversation(
			prompt,
			selectedChoice.provider,
			selectedChoice.model,
		);
		store.ui.addToHistory(prompt);
		store.ui.setQuery("");
		store.ui.focusWidget(Widget.AI_CHAT);
	};

	launchRef.current = launchConversation;

	useEffect(() => {
		solNative.turnOnHorizontalArrowsListeners();
		const subscription = solNative.addListener("keyDown", (event) => {
			if (event.keyCode === 123) moveSelection(-1);
			if (event.keyCode === 124) moveSelection(1);
			if (
				event.keyCode === 36 &&
				!event.meta &&
				!event.shift &&
				!event.control
			) {
				launchRef.current();
			}
		});
		return () => {
			subscription.remove();
			solNative.turnOffHorizontalArrowsListeners();
		};
	}, []);

	useEffect(() => {
		scrollView.current?.scrollTo({
			x: Math.max(0, selectedIndex * 252 - 24),
			animated: true,
		});
	}, [selectedIndex]);

	return (
		<View className="fullWindow">
			<View className="h-14 px-4 flex-row items-center gap-3 border-b border-color">
				<BackButton onPress={() => store.ui.focusWidget(Widget.SEARCH)} />
				<View className="flex-1">
					<Text className="text-lg font-semibold text">Choose an AI model</Text>
					<Text className="text-xs darker-text">
						OpenWebUI is selected first
					</Text>
				</View>
				<TouchableOpacity className="px-2.5 py-1.5" onPress={() => void refreshModels()}>
					<Text className="text-xs text-accent">Refresh</Text>
				</TouchableOpacity>
				<TouchableOpacity
					className="px-2.5 py-1.5"
					onPress={() => {
						store.ui.setSettingsSection("AI");
						store.ui.focusWidget(Widget.SETTINGS);
					}}
				>
					<Text className="text-xs text">Settings</Text>
				</TouchableOpacity>
			</View>

			<View className="px-5 py-4 border-b border-color">
				<Text className="text-xs darker-text mb-1">Prompt</Text>
				<Text numberOfLines={3} className="text-base text leading-5">
					{store.ui.query}
				</Text>
			</View>

			<View className="flex-1 py-5">
				<View className="px-5 mb-3 flex-row items-center">
					<Text className="flex-1 text-sm font-semibold text">Model</Text>
					<Text className="text-xs darker-text">Use ← and →</Text>
				</View>
				<ScrollView
					ref={scrollView}
					horizontal
					showsHorizontalScrollIndicator={false}
					contentContainerStyle={{ paddingHorizontal: 20, gap: 12 }}
				>
					{choices.map((choice, index) => {
						const selected = index === selectedIndex;
						return (
							<TouchableOpacity
								key={choice.key}
								disabled={choice.disabled}
								onPress={() => setSelectedKey(choice.key)}
								className={`h-28 px-4 py-3 border rounded-lg justify-between ${
									selected
										? "border-accent-strong subBg"
										: "border-color"
								} ${choice.disabled ? "opacity-60" : ""}`}
								style={{ width: 240 }}
							>
								<View className="flex-row items-center">
									<Text className="flex-1 text-xs text-accent">
										{PROVIDER_LABELS[choice.provider]}
									</Text>
									{choice.loading && <ActivityIndicator size="small" />}
								</View>
								<Text numberOfLines={2} className="text-sm font-semibold text">
									{choice.name}
								</Text>
								<Text numberOfLines={1} className="text-xs darker-text">
									{choice.model || "Unavailable"}
								</Text>
							</TouchableOpacity>
						);
					})}
				</ScrollView>
			</View>

			<View className="h-10 px-4 flex-row items-center justify-end gap-1 subBg border-t border-color">
				<Text className="text-xs darker-text mr-1">Choose</Text>
				<Key symbol="←" />
				<Key symbol="→" />
				<View className="mx-2" />
				<Text className="text-xs darker-text mr-1">Send prompt</Text>
				<Key
					symbol="⏎"
					primary={!!selectedChoice && !selectedChoice.disabled}
				/>
			</View>
		</View>
	);
});
