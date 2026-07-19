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
import { isOfficialOpenAIAPIBaseURL } from "lib/aiHttp";
import {
	accumulateOpenAIRequestWithoutUsage,
	accumulateOpenAIUsageCost,
	accumulateUnpricedOpenAIUsage,
	createEmptyOpenAILifetimeCost,
	restoreOpenAILifetimeCost,
} from "lib/openaiPricing";
import { autorun, makeAutoObservable, runInAction, toJS } from "mobx";
import { v4 as uuidv4 } from "uuid";
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
	conversation?: unknown;
	conversations?: unknown;
	activeConversationID?: unknown;
	openAILifetimeCost?: unknown;
};

export type AIConversation = {
	id: string;
	title: string;
	messages: AIMessage[];
	createdAt: number;
	updatedAt: number;
	provider?: AIProvider;
	model?: string;
};

const CONVERSATION_TITLE_LIMIT = 64;

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

function normalizeConversation(value: unknown): AIMessage[] {
	if (!Array.isArray(value)) return [];
	return value.flatMap((candidate) => {
		if (typeof candidate !== "object" || candidate === null) return [];
		const message = candidate as Partial<AIMessage>;
		if (
			(message.role !== "user" && message.role !== "assistant") ||
			typeof message.content !== "string"
		) {
			return [];
		}
		return [{ role: message.role, content: message.content }];
	});
}

function conversationTitle(messages: AIMessage[]) {
	const firstPrompt = messages.find((message) => message.role === "user")?.content;
	const title = firstPrompt?.replace(/\s+/g, " ").trim() || "Conversation";
	return title.length > CONVERSATION_TITLE_LIMIT
		? `${title.slice(0, CONVERSATION_TITLE_LIMIT - 1)}…`
		: title;
}

function cloneConversation(conversation: AIConversation): AIConversation {
	return {
		...conversation,
		messages: conversation.messages.map((message) => ({ ...message })),
	};
}

function normalizeConversations(value: unknown): AIConversation[] {
	if (!Array.isArray(value)) return [];
	const usedIDs = new Set<string>();
	const now = Date.now();

	return value
		.flatMap((candidate) => {
			if (typeof candidate !== "object" || candidate === null) return [];
			const record = candidate as Record<string, unknown>;
			const messages = normalizeConversation(record.messages);
			if (messages.length === 0) return [];

			let id =
				typeof record.id === "string" && record.id.trim()
					? record.id
					: uuidv4();
			while (usedIDs.has(id)) id = uuidv4();
			usedIDs.add(id);

			const createdAt =
				typeof record.createdAt === "number" &&
				Number.isFinite(record.createdAt)
					? record.createdAt
					: now;
			const updatedAt =
				typeof record.updatedAt === "number" &&
				Number.isFinite(record.updatedAt)
					? record.updatedAt
					: createdAt;
			const provider =
				record.provider === "openai" || record.provider === "openwebui"
					? record.provider
					: undefined;

			return [
				{
					id,
					title:
						typeof record.title === "string" && record.title.trim()
							? record.title.trim()
							: conversationTitle(messages),
					messages,
					createdAt,
					updatedAt,
					...(provider ? { provider } : {}),
					...(typeof record.model === "string"
						? { model: record.model }
						: {}),
				},
			];
		})
		.sort((left, right) => right.updatedAt - left.updatedAt);
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
			conversations: store.conversations.map(cloneConversation),
			activeConversationID: store.activeConversationID,
			openAILifetimeCost: toJS(store.openAILifetimeCost),
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
		conversations: [] as AIConversation[],
		activeConversationID: null as string | null,
		openAILifetimeCost: createEmptyOpenAILifetimeCost(),
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

		get activeConversation(): AIConversation | null {
			return (
				store.conversations.find(
					(conversation) => conversation.id === store.activeConversationID,
				) ?? null
			);
		},

		get conversation(): AIMessage[] {
			return store.activeConversation?.messages ?? [];
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

		startNewConversation() {
			store.activeConversationID = null;
			store.hasPersistedSettings = true;
		},

		openConversation(conversationID: string) {
			if (
				!store.conversations.some(
					(conversation) => conversation.id === conversationID,
				)
			) {
				return false;
			}
			store.activeConversationID = conversationID;
			store.hasPersistedSettings = true;
			return true;
		},

		saveCurrentConversation(messages: AIMessage[]) {
			const copiedMessages = messages.map((message) => ({ ...message }));
			if (copiedMessages.length === 0) {
				store.startNewConversation();
				return null;
			}

			const now = Date.now();
			const provider = store.settings.provider;
			const model = store.settings[provider].model;
			const existing = store.activeConversation;
			const conversation: AIConversation = existing
				? {
						...existing,
						title: conversationTitle(copiedMessages),
						messages: copiedMessages,
						updatedAt: now,
						provider,
						model,
					}
				: {
						id: uuidv4(),
						title: conversationTitle(copiedMessages),
						messages: copiedMessages,
						createdAt: now,
						updatedAt: now,
						provider,
						model,
					};

			store.conversations = [
				conversation,
				...store.conversations.filter(
					(candidate) => candidate.id !== conversation.id,
				),
			];
			store.activeConversationID = conversation.id;
			store.hasPersistedSettings = true;
			return conversation.id;
		},

		updateConversation(conversationID: string, messages: AIMessage[]) {
			const existing = store.conversations.find(
				(conversation) => conversation.id === conversationID,
			);
			if (!existing) return false;

			const copiedMessages = messages.map((message) => ({ ...message }));
			const updated: AIConversation = {
				...existing,
				title: conversationTitle(copiedMessages),
				messages: copiedMessages,
				updatedAt: Date.now(),
			};
			store.conversations = [
				updated,
				...store.conversations.filter(
					(conversation) => conversation.id !== conversationID,
				),
			];
			store.hasPersistedSettings = true;
			return true;
		},

		deleteConversation(conversationID: string) {
			const nextConversations = store.conversations.filter(
				(conversation) => conversation.id !== conversationID,
			);
			if (nextConversations.length === store.conversations.length) return false;
			store.conversations = nextConversations;
			if (store.activeConversationID === conversationID) {
				store.activeConversationID = nextConversations[0]?.id ?? null;
			}
			store.hasPersistedSettings = true;
			return true;
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
			const result = await requestAI(provider, settings, messages);
			if (provider === "openai") {
				const { lifetime } = result.usage
					? isOfficialOpenAIAPIBaseURL(settings.baseURL) &&
						(result.serviceTier == null || result.serviceTier === "default")
						? accumulateOpenAIUsageCost(
								store.openAILifetimeCost,
								result.usage,
							)
						: accumulateUnpricedOpenAIUsage(
								store.openAILifetimeCost,
								result.usage,
								isOfficialOpenAIAPIBaseURL(settings.baseURL)
									? "non-standard-service-tier"
									: "non-official-endpoint",
							)
					: accumulateOpenAIRequestWithoutUsage(
							store.openAILifetimeCost,
							result.model,
						);
				runInAction(() => {
					store.openAILifetimeCost = lifetime;
				});
			}
			if (!result.text) throw new Error("The API returned no text");
			return result.text;
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
					const settings = mergePersistedSettings(
						cloneDefaultSettings(),
						persistedState?.settings,
					);
					let conversations = normalizeConversations(
						persistedState?.conversations,
					);
					const legacyConversation = normalizeConversation(
						persistedState?.conversation,
					);
					if (conversations.length === 0 && legacyConversation.length > 0) {
						const now = Date.now();
						conversations = [
							{
								id: uuidv4(),
								title: conversationTitle(legacyConversation),
								messages: legacyConversation,
								createdAt: now,
								updatedAt: now,
								provider: settings.provider,
								model: settings[settings.provider].model,
							},
						];
					}
					const persistedActiveID = persistedState?.activeConversationID;
					const activeConversationID =
						typeof persistedActiveID === "string" &&
						conversations.some(
							(conversation) => conversation.id === persistedActiveID,
						)
							? persistedActiveID
							: persistedActiveID === null
								? null
								: (conversations[0]?.id ?? null);

					store.settings = settings;
					store.hasPersistedSettings = persistedState != null;
					store.conversations = conversations;
					store.activeConversationID = activeConversationID;
					store.openAILifetimeCost = restoreOpenAILifetimeCost(
						persistedState?.openAILifetimeCost,
					);
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
