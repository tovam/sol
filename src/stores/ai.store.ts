import {
	DEFAULT_AI_SETTINGS,
	fetchAIModels,
	loadAISettings,
	requestAI,
	saveAISettings,
	type AIMessage,
	type AIProvider,
	type AIProviderSettings,
	type AISettings,
} from "lib/ai";
import type { AIModelInfo } from "lib/aiModels";
import { autorun, makeAutoObservable, runInAction, toJS } from "mobx";
import { readPersistedStore, writePersistedStore } from "./persisted-config";

type PersistedProviderSettings = Pick<
	AIProviderSettings,
	"baseURL" | "model"
>;

type PersistedAISettings = {
	provider: AIProvider;
	openai: PersistedProviderSettings;
	openwebui: PersistedProviderSettings;
};

type PersistedAIState = {
	settings?: Partial<PersistedAISettings>;
};

const cloneDefaultSettings = (): AISettings => ({
	provider: DEFAULT_AI_SETTINGS.provider,
	openai: { ...DEFAULT_AI_SETTINGS.openai },
	openwebui: { ...DEFAULT_AI_SETTINGS.openwebui },
});

function readString(value: unknown, fallback: string) {
	return typeof value === "string" ? value : fallback;
}

function mergePersistedSettings(
	secureSettings: AISettings,
	persistedSettings?: Partial<PersistedAISettings>,
): AISettings {
	const provider =
		persistedSettings?.provider === "openwebui" ||
		persistedSettings?.provider === "openai"
			? persistedSettings.provider
			: secureSettings.provider;

	return {
		provider,
		openai: {
			...secureSettings.openai,
			baseURL: readString(
				persistedSettings?.openai?.baseURL,
				secureSettings.openai.baseURL,
			),
			model: readString(
				persistedSettings?.openai?.model,
				secureSettings.openai.model,
			),
		},
		openwebui: {
			...secureSettings.openwebui,
			baseURL: readString(
				persistedSettings?.openwebui?.baseURL,
				secureSettings.openwebui.baseURL,
			),
			model: readString(
				persistedSettings?.openwebui?.model,
				secureSettings.openwebui.model,
			),
		},
	};
}

function persistentSettings(settings: AISettings): PersistedAISettings {
	return {
		provider: settings.provider,
		openai: {
			baseURL: settings.openai.baseURL,
			model: settings.openai.model,
		},
		openwebui: {
			baseURL: settings.openwebui.baseURL,
			model: settings.openwebui.model,
		},
	};
}

export function validateAIProviderSettings(
	provider: AIProvider,
	settings: AIProviderSettings,
): string | null {
	if (!settings.baseURL.trim()) return "Enter the API server URL";
	if (!settings.model.trim()) return "Choose a model";
	if (provider === "openai" && !settings.apiKey.trim()) {
		return "Enter your OpenAI API key";
	}
	return null;
}

export type AIStore = ReturnType<typeof createAIStore>;

export const createAIStore = () => {
	let persistDisposer: (() => void) | undefined;
	let initializationPromise: Promise<void> | undefined;
	let secretsPromise: Promise<void> | undefined;
	let disposed = false;
	const requestSequence: Record<AIProvider, number> = {
		openai: 0,
		openwebui: 0,
	};

	const persist = () => {
		if (!store.hasPersistedSettings && !store.secretsLoaded) return;
		writePersistedStore("ai", {
			settings: persistentSettings(store.settings),
		});
	};

	const store = makeAutoObservable({
		settings: cloneDefaultSettings(),
		initialized: false,
		initializationError: "",
		hasPersistedSettings: false,
		secretsLoaded: false,
		secretsLoading: false,
		secretsAttempted: false,
		secretsError: "",
		modelsByProvider: {
			openai: [] as AIModelInfo[],
			openwebui: [] as AIModelInfo[],
		},
		modelsLoading: {
			openai: false,
			openwebui: false,
		},
		modelsError: {
			openai: "",
			openwebui: "",
		},

		get currentSettings() {
			return store.settings[store.settings.provider];
		},

		get currentModelOptions(): AIModelInfo[] {
			const provider = store.settings.provider;
			const currentModel = store.settings[provider].model.trim();
			const options = store.modelsByProvider[provider];
			if (!currentModel || options.some((option) => option.id === currentModel)) {
				return options;
			}
			return [{ id: currentModel, name: currentModel }, ...options];
		},

		setProvider(provider: AIProvider) {
			store.settings = { ...store.settings, provider };
			store.hasPersistedSettings = true;
		},

		updateProviderSettings(
			provider: AIProvider,
			key: keyof AIProviderSettings,
			value: string,
		) {
			const connectionChanged =
				(key === "baseURL" || key === "apiKey") &&
				store.settings[provider][key] !== value;
			store.settings = {
				...store.settings,
				[provider]: {
					...store.settings[provider],
					[key]: value,
				},
			};
			if (key === "baseURL" || key === "model") {
				store.hasPersistedSettings = true;
			}
			if (key === "apiKey") {
				store.secretsLoaded = true;
				store.secretsAttempted = true;
				store.secretsError = "";
			}
			if (connectionChanged) {
				requestSequence[provider] += 1;
				store.modelsByProvider = {
					...store.modelsByProvider,
					[provider]: [],
				};
				store.modelsLoading = {
					...store.modelsLoading,
					[provider]: false,
				};
				store.modelsError = { ...store.modelsError, [provider]: "" };
			}
		},

		setModel(provider: AIProvider, model: string) {
			store.updateProviderSettings(provider, "model", model);
		},

		ensureSecretsLoaded: async (force = false) => {
			await initializationPromise;
			if (
				disposed ||
				store.secretsLoaded ||
				(store.secretsAttempted && !force)
			) {
				return;
			}
			if (secretsPromise) return secretsPromise;

			runInAction(() => {
				store.secretsLoading = true;
				store.secretsError = "";
			});

			secretsPromise = (async () => {
				try {
					const secureSettings = await loadAISettings();
					if (disposed) return;
					runInAction(() => {
						store.settings = store.hasPersistedSettings
							? {
									...store.settings,
									openai: {
										...store.settings.openai,
										apiKey: secureSettings.openai.apiKey,
									},
									openwebui: {
										...store.settings.openwebui,
										apiKey: secureSettings.openwebui.apiKey,
									},
								}
							: secureSettings;
						store.hasPersistedSettings = true;
						store.secretsLoaded = true;
						store.secretsAttempted = true;
						store.secretsError = "";
					});
				} catch (error) {
					if (disposed) return;
					runInAction(() => {
						store.secretsAttempted = true;
						store.secretsError =
							error instanceof Error
								? error.message
								: "Could not load API keys from Keychain";
					});
				} finally {
					if (!disposed) {
						runInAction(() => {
							store.secretsLoading = false;
						});
					}
					secretsPromise = undefined;
				}
			})();

			return secretsPromise;
		},

		refreshModels: async (provider: AIProvider) => {
			await store.ensureSecretsLoaded();
			if (disposed) return;
			const settings = { ...store.settings[provider] };
			if (!settings.baseURL.trim()) {
				runInAction(() => {
					store.modelsError = {
						...store.modelsError,
						[provider]: "Enter the API server URL",
					};
				});
				return;
			}
			if (provider === "openai" && !settings.apiKey.trim()) {
				runInAction(() => {
					store.modelsError = {
						...store.modelsError,
						[provider]: store.secretsError || "Enter your OpenAI API key",
					};
				});
				return;
			}
			const requestID = ++requestSequence[provider];
			runInAction(() => {
				store.modelsLoading = {
					...store.modelsLoading,
					[provider]: true,
				};
				store.modelsError = { ...store.modelsError, [provider]: "" };
			});

			try {
				const models = await fetchAIModels(provider, settings);
				if (requestSequence[provider] !== requestID) return;
				runInAction(() => {
					store.modelsByProvider = {
						...store.modelsByProvider,
						[provider]: models,
					};
					store.modelsError = {
						...store.modelsError,
						[provider]:
							models.length === 0
								? provider === "openwebui"
									? "No qwen, llama, deepseek or phi text model was returned"
									: "No compatible text model was returned"
								: "",
					};
				});
			} catch (error) {
				if (requestSequence[provider] !== requestID) return;
				runInAction(() => {
					store.modelsError = {
						...store.modelsError,
						[provider]:
							error instanceof Error
								? error.message
								: "Could not load models",
					};
				});
			} finally {
				if (requestSequence[provider] === requestID) {
					runInAction(() => {
						store.modelsLoading = {
							...store.modelsLoading,
							[provider]: false,
						};
					});
				}
			}
		},

		request: async (messages: AIMessage[]) => {
			await store.ensureSecretsLoaded();
			const provider = store.settings.provider;
			const settings = { ...store.settings[provider] };
			const validationError = validateAIProviderSettings(provider, settings);
			if (validationError) throw new Error(validationError);
			return requestAI(provider, settings, messages);
		},

		saveSecureSettings: async () => {
			await saveAISettings(toJS(store.settings) as AISettings);
			runInAction(() => {
				store.hasPersistedSettings = true;
				store.secretsLoaded = true;
				store.secretsAttempted = true;
				store.secretsError = "";
			});
		},

		initialize: async () => {
			try {
				const persistedState =
					await readPersistedStore<PersistedAIState>("ai");
				if (disposed) return;
				runInAction(() => {
					store.settings = mergePersistedSettings(
						cloneDefaultSettings(),
						persistedState?.settings,
					);
					store.hasPersistedSettings = persistedState?.settings != null;
				});
			} catch (error) {
				if (disposed) return;
				runInAction(() => {
					store.initializationError =
						error instanceof Error
							? error.message
							: "Could not load AI settings";
				});
			} finally {
				if (disposed) return;
				runInAction(() => {
					store.initialized = true;
				});
				persistDisposer?.();
				persistDisposer = autorun(persist);
			}
		},

		cleanUp() {
			disposed = true;
			requestSequence.openai += 1;
			requestSequence.openwebui += 1;
			persistDisposer?.();
		},
	});

	initializationPromise = store.initialize();

	return store;
};
