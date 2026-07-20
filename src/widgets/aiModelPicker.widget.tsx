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
	id: string;
	name: string;
};

export const AIModelPickerWidget = observer(() => {
	const store = useStore();
	const requestedProviders = useRef(new Set<AIProvider>());
	const modelScrollRef = useRef<ScrollView>(null);
	const providerRef = useRef<AIProvider>("openwebui");
	const modelChoicesRef = useRef<ModelChoice[]>([]);
	const selectedModelRef = useRef("");
	const highlightedIndexRef = useRef(0);
	const menuOpenRef = useRef(false);
	const canLaunchRef = useRef(false);
	const launchRef = useRef<(provider: AIProvider, model: string) => void>(
		() => undefined,
	);
	const [provider, setProvider] = useState<AIProvider>("openwebui");
	const [selectedModels, setSelectedModels] = useState<
		Record<AIProvider, string | null>
	>({
		openwebui: null,
		openai: null,
	});
	const selectedModelsRef = useRef(selectedModels);
	const [menuOpen, setMenuOpen] = useState(false);
	const [highlightedIndex, setHighlightedIndex] = useState(0);

	const getModelChoices = (modelProvider: AIProvider): ModelChoice[] => {
		const configuredModel = store.ai.settings[modelProvider].model.trim();
		const seenModels = new Set<string>();
		const choices: ModelChoice[] = [];

		for (const model of store.ai.modelsByProvider[modelProvider]) {
			if (seenModels.has(model.id)) continue;
			seenModels.add(model.id);
			choices.push({ id: model.id, name: model.name || model.id });
		}

		if (configuredModel && !seenModels.has(configuredModel)) {
			choices.unshift({ id: configuredModel, name: configuredModel });
		}
		return choices;
	};

	const configuredModel = store.ai.settings[provider].model.trim();
	const modelChoices = getModelChoices(provider);

	const requestedModel = (selectedModels[provider] ?? configuredModel).trim();
	const selectedModel = modelChoices.some(
		(choice) => choice.id === requestedModel,
	)
		? requestedModel
		: (modelChoices[0]?.id ?? "");
	const selectedChoice = modelChoices.find(
		(choice) => choice.id === selectedModel,
	);
	const safeHighlightedIndex = Math.min(
		Math.max(0, highlightedIndex),
		Math.max(0, modelChoices.length - 1),
	);
	const loading =
		store.ai.secretsLoading || store.ai.modelsLoading[provider];
	const error =
		store.ai.modelsError[provider] ||
		store.ai.secretsError ||
		store.ai.initializationError;

	providerRef.current = provider;
	modelChoicesRef.current = modelChoices;
	selectedModelRef.current = selectedModel;
	selectedModelsRef.current = selectedModels;
	highlightedIndexRef.current = safeHighlightedIndex;
	menuOpenRef.current = menuOpen;
	canLaunchRef.current = !loading && !!selectedModel;

	const closeMenu = () => {
		menuOpenRef.current = false;
		setMenuOpen(false);
	};

	const chooseProvider = (nextProvider: AIProvider) => {
		const choices = getModelChoices(nextProvider);
		const configured = store.ai.settings[nextProvider].model.trim();
		const requested = (
			selectedModelsRef.current[nextProvider] ?? configured
		).trim();
		const model = choices.some((choice) => choice.id === requested)
			? requested
			: (choices[0]?.id ?? "");
		const nextHighlightedIndex = Math.max(
			0,
			choices.findIndex((choice) => choice.id === model),
		);
		providerRef.current = nextProvider;
		modelChoicesRef.current = choices;
		selectedModelRef.current = model;
		highlightedIndexRef.current = nextHighlightedIndex;
		canLaunchRef.current =
			!store.ai.secretsLoading &&
			!store.ai.modelsLoading[nextProvider] &&
			!!model;
		setProvider(nextProvider);
		setHighlightedIndex(nextHighlightedIndex);
		closeMenu();
	};

	const chooseModel = (model: string) => {
		const selectedProvider = providerRef.current;
		selectedModelsRef.current = {
			...selectedModelsRef.current,
			[selectedProvider]: model,
		};
		selectedModelRef.current = model;
		setSelectedModels((current) => ({
			...current,
			[selectedProvider]: model,
		}));
	};

	const openMenu = () => {
		const choices = modelChoicesRef.current;
		if (choices.length === 0) return;
		const selectedIndex = choices.findIndex(
			(choice) => choice.id === selectedModelRef.current,
		);
		const nextIndex = selectedIndex >= 0 ? selectedIndex : 0;
		highlightedIndexRef.current = nextIndex;
		setHighlightedIndex(nextIndex);
		menuOpenRef.current = true;
		setMenuOpen(true);
	};

	const toggleMenu = () => {
		if (menuOpenRef.current) closeMenu();
		else openMenu();
	};

	const moveHighlight = (direction: -1 | 1) => {
		const choices = modelChoicesRef.current;
		if (choices.length === 0) return;
		if (!menuOpenRef.current) {
			openMenu();
			return;
		}
		const nextIndex =
			(highlightedIndexRef.current + direction + choices.length) %
			choices.length;
		highlightedIndexRef.current = nextIndex;
		setHighlightedIndex(nextIndex);
	};

	const launchConversation = (
		selectedProvider: AIProvider,
		model: string,
	) => {
		if (
			!model ||
			store.ai.secretsLoading ||
			store.ai.modelsLoading[selectedProvider]
		) {
			return;
		}
		const prompt = store.ui.query.trim();
		if (!prompt) {
			store.ui.focusWidget(Widget.SEARCH);
			return;
		}

		store.ai.setProvider(selectedProvider);
		store.ai.setModel(selectedProvider, model);
		store.ai.startNewConversation();
		store.ai.queueConversation(prompt, selectedProvider, model);
		store.ui.addToHistory(prompt);
		store.ui.setQuery("");
		store.ui.focusWidget(Widget.AI_CHAT);
	};

	launchRef.current = launchConversation;

	useEffect(() => {
		if (requestedProviders.current.has(provider)) return;
		requestedProviders.current.add(provider);
		if (store.ai.modelsByProvider[provider].length === 0) {
			void store.ai.refreshModels(provider);
		}
		// The AI store is stable for the lifetime of this widget.
		// eslint-disable-next-line react-hooks/exhaustive-deps
	}, [provider]);

	useEffect(() => {
		if (!menuOpen) return;
		modelScrollRef.current?.scrollTo({
			y: Math.max(0, safeHighlightedIndex * 44 - 88),
			animated: true,
		});
	}, [menuOpen, safeHighlightedIndex]);

	useEffect(() => {
		if (!loading) return;
		menuOpenRef.current = false;
		setMenuOpen(false);
	}, [loading]);

	useEffect(() => {
		solNative.turnOnHorizontalArrowsListeners();
		const subscription = solNative.addListener("keyDown", (event) => {
			if (event.meta || event.shift || event.control) return;

			if (event.keyCode === 123 || event.keyCode === 124) {
				const currentIndex = PROVIDERS.indexOf(providerRef.current);
				const direction = event.keyCode === 123 ? -1 : 1;
				const nextIndex =
					(currentIndex + direction + PROVIDERS.length) % PROVIDERS.length;
				chooseProvider(PROVIDERS[nextIndex]);
				return;
			}

			if (event.keyCode === 126 || event.keyCode === 125) {
				moveHighlight(event.keyCode === 126 ? -1 : 1);
				return;
			}

			if (event.keyCode === 36) {
				if (!canLaunchRef.current) return;
				const currentProvider = providerRef.current;
				let model = selectedModelRef.current;
				if (menuOpenRef.current) {
					model =
						modelChoicesRef.current[highlightedIndexRef.current]?.id ?? model;
					chooseModel(model);
					closeMenu();
				}
				launchRef.current(currentProvider, model);
			}
		});
		return () => {
			subscription.remove();
			solNative.turnOffHorizontalArrowsListeners();
		};
		// Keyboard actions read the current selection through refs.
		// eslint-disable-next-line react-hooks/exhaustive-deps
	}, []);

	return (
		<View className="fullWindow">
			<View className="h-14 px-4 flex-row items-center gap-3 border-b border-color">
				<BackButton onPress={() => store.ui.focusWidget(Widget.SEARCH)} />
				<View className="flex-1">
					<Text className="text-lg font-semibold text">Start an AI conversation</Text>
					<Text className="text-xs darker-text">
						Choose a provider and a text model
					</Text>
				</View>
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

			<View className="px-5 py-3 border-b border-color">
				<Text className="text-xs darker-text mb-1">Prompt</Text>
				<Text numberOfLines={2} className="text-sm text leading-5">
					{store.ui.query}
				</Text>
			</View>

			<View className="flex-1 px-5 py-5" style={{ zIndex: 20 }}>
				<Text className="text-xs darker-text mb-2">Provider and model</Text>
				<View className="flex-row items-start gap-2" style={{ zIndex: 30 }}>
					<View className="h-9 flex-row p-0.5 rounded-lg border border-color subBg">
						{PROVIDERS.map((option) => {
							const selected = option === provider;
							return (
								<TouchableOpacity
									key={option}
									className={`px-3 rounded-md items-center justify-center ${
										selected ? "bg-accent-strong" : ""
									}`}
									onPress={() => chooseProvider(option)}
								>
									<Text
										className={`text-xs ${
											selected ? "text-white font-semibold" : "text"
										}`}
									>
										{PROVIDER_LABELS[option]}
									</Text>
								</TouchableOpacity>
							);
						})}
					</View>

					<View className="flex-1" style={{ minWidth: 0, zIndex: 40 }}>
						<TouchableOpacity
							disabled={loading || modelChoices.length === 0}
							className={`h-9 px-3 rounded-lg border flex-row items-center border-color subBg ${
								loading || modelChoices.length === 0 ? "opacity-60" : ""
							}`}
							onPress={toggleMenu}
						>
							<Text className="flex-1 text-sm text" numberOfLines={1}>
								{loading
									? "Loading models…"
									: (selectedChoice?.name ?? "No compatible model")}
							</Text>
							<Text className="ml-2 darker-text">{menuOpen ? "⌃" : "⌄"}</Text>
						</TouchableOpacity>

						{menuOpen && (
							<View
								className="absolute left-0 right-0 rounded-lg border border-color bg-white dark:bg-neutral-800 p-1"
								style={{ top: 40, zIndex: 100 }}
							>
								<ScrollView
									ref={modelScrollRef}
									style={{ maxHeight: 180 }}
									showsVerticalScrollIndicator={false}
								>
									{modelChoices.map((choice, index) => {
										const highlighted = index === safeHighlightedIndex;
										const selected = choice.id === selectedModel;
										return (
											<TouchableOpacity
												key={choice.id}
												className={`px-3 py-2 rounded-md ${
													highlighted ? "subBg" : ""
												}`}
												onMouseEnter={() => {
													highlightedIndexRef.current = index;
													setHighlightedIndex(index);
												}}
												onPress={() => {
													chooseModel(choice.id);
													closeMenu();
												}}
											>
												<View className="h-7 flex-row items-center gap-2">
													<Text
														className={`flex-1 text-sm ${
															selected ? "text-accent font-semibold" : "text"
														}`}
														numberOfLines={1}
													>
														{choice.name === choice.id
															? choice.id
															: `${choice.name} — ${choice.id}`}
													</Text>
													{selected && <Text className="text-accent">✓</Text>}
												</View>
											</TouchableOpacity>
										);
									})}
								</ScrollView>
							</View>
						)}
					</View>

					<TouchableOpacity
						disabled={loading}
						className={`h-9 w-9 rounded-lg border border-color subBg items-center justify-center ${
							loading ? "opacity-50" : ""
						}`}
						onPress={() => void store.ai.refreshModels(provider)}
					>
						{loading ? (
							<ActivityIndicator size="small" />
						) : (
							<Text className={error ? "text-red-500" : "text"}>↻</Text>
						)}
					</TouchableOpacity>

					<TouchableOpacity
						disabled={loading || !selectedModel}
						className={`h-9 px-4 rounded-lg items-center justify-center bg-accent-strong ${
							loading || !selectedModel ? "opacity-50" : ""
						}`}
						onPress={() => launchConversation(provider, selectedModel)}
					>
						<Text className="text-xs text-white font-semibold">Start</Text>
					</TouchableOpacity>
				</View>

				{!!error && !loading && (
					<Text className="text-xs text-red-500 mt-2" numberOfLines={2}>
						{error}
					</Text>
				)}
			</View>

			<View className="h-10 px-4 flex-row items-center justify-end gap-1 subBg border-t border-color">
				<Text className="text-xs darker-text mr-1">Provider</Text>
				<Key symbol="←" />
				<Key symbol="→" />
				<View className="mx-2" />
				<Text className="text-xs darker-text mr-1">Models</Text>
				<Key symbol="↑" />
				<Key symbol="↓" />
				<View className="mx-2" />
				<Text className="text-xs darker-text mr-1">Start</Text>
				<Key symbol="⏎" primary={!!selectedModel && !loading} />
			</View>
		</View>
	);
});
