import axios from "axios";
import {
	createAIHeaders,
	isOfficialOpenAIAPIBaseURL,
	openAIEndpoint,
	openAIModelsEndpoint,
	openWebUIEndpoint,
	openWebUIModelsEndpoint,
} from "lib/aiHttp";
import {
	filterOpenAITextModels,
	filterOpenWebUITextModels,
	parseAIModelsResponse,
} from "lib/aiModels";
import type { OpenAITokenUsage } from "lib/openaiPricing";
import { solNative } from "lib/SolNative";
import { v4 as uuidv4 } from "uuid";

export type AIProvider = "openai" | "openwebui";

export type AIMessage = {
	role: "user" | "assistant";
	content: string;
};

export type AIProviderSettings = {
	baseURL: string;
	model: string;
	apiKey: string;
};

export type AISettings = {
	provider: AIProvider;
	openai: AIProviderSettings;
	openwebui: AIProviderSettings;
};

export type AIRequestResult = {
	text: string;
	provider: AIProvider;
	model: string;
	serviceTier?: string;
	usage?: OpenAITokenUsage;
};

export type AIStreamingRequest = {
	requestID: string;
	result: Promise<AIRequestResult>;
	cancel: () => void;
};

export class AIStreamCancelledError extends Error {
	constructor() {
		super("The response was stopped");
		this.name = "AIStreamCancelledError";
	}
}

export function isAIStreamCancelledError(error: unknown) {
	return (
		error instanceof AIStreamCancelledError ||
		asRecord(error)?.name === "AIStreamCancelledError"
	);
}

const LEGACY_AI_SECRETS_FILE_PATH = `/Users/${solNative.userName()}/.config/sol/ai-secrets.json`;

export const DEFAULT_AI_SETTINGS: AISettings = {
	provider: "openai",
	openai: {
		baseURL: "https://api.openai.com/v1",
		model: "gpt-5.6-sol",
		apiKey: "",
	},
	openwebui: {
		baseURL: "http://localhost:3000",
		model: "",
		apiKey: "",
	},
};

function asRecord(value: unknown): Record<string, unknown> | null {
	return typeof value === "object" && value !== null
		? (value as Record<string, unknown>)
		: null;
}

function extractOpenAIText(data: unknown) {
	const root = asRecord(data);
	if (!root) return "";
	if (typeof root.output_text === "string") return root.output_text;
	if (!Array.isArray(root.output)) return "";

	const parts: string[] = [];
	for (const outputItem of root.output) {
		const item = asRecord(outputItem);
		if (!item || !Array.isArray(item.content)) continue;
		for (const contentItem of item.content) {
			const content = asRecord(contentItem);
			if (content && typeof content.text === "string") {
				parts.push(content.text);
			} else if (content && typeof content.refusal === "string") {
				parts.push(content.refusal);
			}
		}
	}
	return parts.join("\n");
}

function extractOpenWebUIText(data: unknown) {
	const root = asRecord(data);
	const choices = root?.choices;
	if (!Array.isArray(choices)) return "";
	const firstChoice = asRecord(choices[0]);
	const message = asRecord(firstChoice?.message);
	if (typeof message?.content === "string") return message.content;
	if (!Array.isArray(message?.content)) return "";
	return message.content
		.map((part) => asRecord(part)?.text)
		.filter((part): part is string => typeof part === "string")
		.join("\n");
}

function extractStreamingText(value: unknown): string {
	if (typeof value === "string") return value;
	if (!Array.isArray(value)) return "";
	return value
		.map((part) => {
			if (typeof part === "string") return part;
			const record = asRecord(part);
			if (typeof record?.text === "string") return record.text;
			return typeof record?.content === "string" ? record.content : "";
		})
		.join("");
}

function tokenCount(value: unknown) {
	return typeof value === "number" && Number.isSafeInteger(value) && value >= 0
		? value
		: null;
}

function responseModel(data: unknown, fallback: string) {
	const model = asRecord(data)?.model;
	return typeof model === "string" && model.trim() ? model.trim() : fallback;
}

function responseServiceTier(data: unknown) {
	const serviceTier = asRecord(data)?.service_tier;
	return typeof serviceTier === "string" ? serviceTier : undefined;
}

function extractOpenAIUsage(
	data: unknown,
	fallbackModel: string,
): OpenAITokenUsage | undefined {
	const root = asRecord(data);
	const usage = asRecord(root?.usage);
	const inputTokens = tokenCount(usage?.input_tokens);
	const outputTokens = tokenCount(usage?.output_tokens);
	if (inputTokens == null || outputTokens == null) return undefined;

	const inputDetails = asRecord(usage?.input_tokens_details);
	return {
		model: responseModel(data, fallbackModel),
		inputTokens,
		outputTokens,
		cachedInputTokens: tokenCount(inputDetails?.cached_tokens) ?? 0,
		cacheWriteTokens:
			tokenCount(inputDetails?.cache_write_tokens) ??
			tokenCount(usage?.cache_write_tokens) ??
			0,
	};
}

function getRequestError(error: unknown, provider: AIProvider) {
	if (!axios.isAxiosError(error)) {
		return error instanceof Error ? error.message : "The request failed";
	}
	const data = asRecord(error.response?.data);
	const apiError = asRecord(data?.error);
	const detail =
		typeof apiError?.message === "string"
			? apiError.message
			: typeof data?.detail === "string"
				? data.detail
				: error.message;
	if (provider === "openwebui" && error.response?.status === 401) {
		return `${detail}. Check that API keys are enabled and accepted by OpenWebUI.`;
	}
	return detail;
}

function payloadErrorMessage(value: unknown, fallback: string) {
	const root = asRecord(value);
	const error = asRecord(root?.error);
	const responseError = asRecord(asRecord(root?.response)?.error);
	if (typeof root?.error === "string") return root.error;
	if (typeof error?.message === "string") return error.message;
	if (typeof responseError?.message === "string") return responseError.message;
	if (typeof root?.detail === "string") return root.detail;
	if (typeof root?.message === "string") return root.message;
	return fallback;
}

type AIStreamDataEvent = {
	requestID?: unknown;
	data?: unknown;
};

type AIStreamCompletedEvent = {
	requestID?: unknown;
	cancelled?: unknown;
};

type AIStreamFailedEvent = {
	requestID?: unknown;
	message?: unknown;
	status?: unknown;
	body?: unknown;
};

function streamFailureError(event: AIStreamFailedEvent, provider: AIProvider) {
	let message =
		typeof event.message === "string"
			? event.message
			: "The streaming request failed";
	if (typeof event.body === "string" && event.body.trim()) {
		try {
			message = payloadErrorMessage(JSON.parse(event.body), message);
		} catch {
			// Keep the transport error when the response is not JSON.
		}
	}
	if (provider === "openwebui" && event.status === 401) {
		message = `${message}. Check that API keys are enabled and accepted by OpenWebUI.`;
	}
	return new Error(message);
}

export async function fetchAIModels(
	provider: AIProvider,
	settings: AIProviderSettings,
) {
	const headers = createAIHeaders(provider, settings.apiKey);
	const endpoint =
		provider === "openai"
			? openAIModelsEndpoint(settings.baseURL)
			: openWebUIModelsEndpoint(settings.baseURL);

	try {
		const response = await axios.get(endpoint, { headers });
		const parsedModels = parseAIModelsResponse(response.data);
		if (provider === "openwebui") {
			return filterOpenWebUITextModels(parsedModels);
		}

		return filterOpenAITextModels(parsedModels).sort((first, second) =>
			second.id.localeCompare(first.id, undefined, { numeric: true }),
		);
	} catch (error) {
		throw new Error(getRequestError(error, provider));
	}
}

function cloneDefaultAISettings(): AISettings {
	return {
		...DEFAULT_AI_SETTINGS,
		openai: { ...DEFAULT_AI_SETTINGS.openai },
		openwebui: { ...DEFAULT_AI_SETTINGS.openwebui },
	};
}

function decodeAISettings(savedValue: string): AISettings | null {
	try {
		const saved = asRecord(JSON.parse(savedValue));
		if (!saved) return null;
		const apiKeys = asRecord(saved?.apiKeys);
		if ((saved.version === 2 || saved.version === 3) && apiKeys) {
			return {
				...cloneDefaultAISettings(),
				openai: {
					...DEFAULT_AI_SETTINGS.openai,
					apiKey:
						typeof apiKeys.openai === "string" ? apiKeys.openai : "",
				},
				openwebui: {
					...DEFAULT_AI_SETTINGS.openwebui,
					apiKey:
						typeof apiKeys.openwebui === "string"
							? apiKeys.openwebui
							: "",
				},
			};
		}

		const savedProvider =
			saved.provider === "openwebui" ? "openwebui" : "openai";
		const savedOpenAI = asRecord(saved.openai);
		const savedOpenWebUI = asRecord(saved.openwebui);
		const decodeLegacyProviderSettings = (
			value: Record<string, unknown> | null,
			defaults: AIProviderSettings,
		): AIProviderSettings => ({
			baseURL:
				typeof value?.baseURL === "string" ? value.baseURL : defaults.baseURL,
			model: typeof value?.model === "string" ? value.model : defaults.model,
			apiKey:
				typeof value?.apiKey === "string" ? value.apiKey : defaults.apiKey,
		});
		return {
			provider: savedProvider,
			openai: decodeLegacyProviderSettings(
				savedOpenAI,
				DEFAULT_AI_SETTINGS.openai,
			),
			openwebui: decodeLegacyProviderSettings(
				savedOpenWebUI,
				DEFAULT_AI_SETTINGS.openwebui,
			),
		};
	} catch {
		return null;
	}
}

function encodeAISecrets(settings: AISettings) {
	return JSON.stringify({
		version: 3,
		apiKeys: {
			openai: settings.openai.apiKey,
			openwebui: settings.openwebui.apiKey,
		},
	});
}

function removeLegacyAISecretsFile() {
	if (!solNative.exists(LEGACY_AI_SECRETS_FILE_PATH)) return;
	try {
		solNative.del(LEGACY_AI_SECRETS_FILE_PATH);
	} catch {
		// The Keychain copy remains authoritative. A later launch retries the
		// cleanup without ever printing or otherwise exposing the file contents.
	}
}

export async function loadAISettings(): Promise<AISettings> {
	const keychainValue = await solNative.readAISecrets();
	if (keychainValue != null) {
		const settings = decodeAISettings(keychainValue);
		if (!settings) {
			throw new Error("The AI credentials stored in Keychain are invalid");
		}
		removeLegacyAISecretsFile();
		return settings;
	}

	const legacyValue = solNative.readFile(LEGACY_AI_SECRETS_FILE_PATH);
	if (!legacyValue) return cloneDefaultAISettings();
	const legacySettings = decodeAISettings(legacyValue);
	if (!legacySettings) return cloneDefaultAISettings();

	await solNative.writeAISecrets(encodeAISecrets(legacySettings));
	removeLegacyAISecretsFile();
	return legacySettings;
}

export async function saveAISettings(settings: AISettings) {
	const didWrite = await solNative.writeAISecrets(encodeAISecrets(settings));
	if (!didWrite) {
		throw new Error("Could not save API keys in the macOS Keychain");
	}
	removeLegacyAISecretsFile();
}

export async function requestAI(
	provider: AIProvider,
	settings: AIProviderSettings,
	messages: AIMessage[],
): Promise<AIRequestResult> {
	const headers = createAIHeaders(provider, settings.apiKey);
	const requestedModel = settings.model.trim();

	try {
		if (provider === "openai") {
			const requestBody = {
				model: requestedModel,
				input: messages,
				...(isOfficialOpenAIAPIBaseURL(settings.baseURL)
					? { service_tier: "default" }
					: {}),
			};
			const response = await axios.post(
				openAIEndpoint(settings.baseURL),
				requestBody,
				{ headers },
			);
			const responseText = extractOpenAIText(response.data);
			return {
				text: responseText,
				provider,
				model: responseModel(response.data, requestedModel),
				serviceTier: responseServiceTier(response.data),
				usage: extractOpenAIUsage(response.data, requestedModel),
			};
		}

		const response = await axios.post(
			openWebUIEndpoint(settings.baseURL),
			{
				model: requestedModel,
				messages,
				stream: false,
			},
			{ headers },
		);
		const responseText = extractOpenWebUIText(response.data);
		if (!responseText) throw new Error("The API returned no text");
		return {
			text: responseText,
			provider,
			model: responseModel(response.data, requestedModel),
		};
	} catch (error) {
		throw new Error(getRequestError(error, provider));
	}
}

export function requestAIStream(
	provider: AIProvider,
	settings: AIProviderSettings,
	messages: AIMessage[],
	onText: (text: string) => void,
): AIStreamingRequest {
	const requestID = uuidv4();
	const requestedModel = settings.model.trim();
	const headers = {
		...createAIHeaders(provider, settings.apiKey),
		Accept: "text/event-stream",
	};
	const endpoint =
		provider === "openai"
			? openAIEndpoint(settings.baseURL)
			: openWebUIEndpoint(settings.baseURL);
	const body: Record<string, unknown> =
		provider === "openai"
			? {
					model: requestedModel,
					input: messages,
					stream: true,
					...(isOfficialOpenAIAPIBaseURL(settings.baseURL)
						? { service_tier: "default" }
						: {}),
				}
			: {
					model: requestedModel,
					messages,
					stream: true,
				};

	let text = "";
	let responseModelID = requestedModel;
	let serviceTier: string | undefined;
	let usage: OpenAITokenUsage | undefined;
	let settled = false;
	let notifyTimer: ReturnType<typeof setTimeout> | null = null;
	let lastNotifiedText = "";

	const notifyText = (immediately = false) => {
		if (immediately) {
			if (notifyTimer) clearTimeout(notifyTimer);
			notifyTimer = null;
			if (text !== lastNotifiedText) {
				lastNotifiedText = text;
				onText(text);
			}
			return;
		}
		if (notifyTimer) return;
		notifyTimer = setTimeout(() => {
			notifyTimer = null;
			if (text === lastNotifiedText) return;
			lastNotifiedText = text;
			onText(text);
		}, 32);
	};

	const appendText = (delta: string) => {
		if (!delta) return;
		text += delta;
		notifyText();
	};

	const replaceWithCompleteText = (completeText: string) => {
		if (!completeText || completeText === text) return;
		text = completeText;
		notifyText();
	};

	let cleanup: () => void = () => undefined;
	let resolveResult: (value: AIRequestResult) => void = () => undefined;
	let rejectResult: (reason: Error) => void = () => undefined;

	const finishWithError = (error: Error) => {
		if (settled) return;
		settled = true;
		notifyText(true);
		cleanup();
		rejectResult(error);
	};

	const finishSuccessfully = () => {
		if (settled) return;
		if (!text) {
			finishWithError(new Error("The API returned no text"));
			return;
		}
		settled = true;
		notifyText(true);
		cleanup();
		resolveResult({
			text,
			provider,
			model: responseModelID,
			serviceTier,
			usage,
		});
	};

	const processOpenAIEvent = (event: Record<string, unknown>) => {
		const eventType = typeof event.type === "string" ? event.type : "";
		if (
			eventType === "response.output_text.delta" ||
			eventType === "response.refusal.delta"
		) {
			appendText(typeof event.delta === "string" ? event.delta : "");
			return;
		}

		if (
			eventType === "response.output_text.done" ||
			eventType === "response.refusal.done"
		) {
			if (!text) {
				replaceWithCompleteText(
					typeof event.text === "string"
						? event.text
						: typeof event.refusal === "string"
							? event.refusal
							: "",
				);
			}
			return;
		}

		if (
			eventType === "response.completed" ||
			eventType === "response.incomplete"
		) {
			const response = event.response;
			replaceWithCompleteText(extractOpenAIText(response));
			responseModelID = responseModel(response, requestedModel);
			serviceTier = responseServiceTier(response);
			usage = extractOpenAIUsage(response, requestedModel);
			return;
		}

		if (eventType === "error" || eventType === "response.failed") {
			throw new Error(payloadErrorMessage(event, "The OpenAI request failed"));
		}
	};

	const processOpenWebUIEvent = (event: Record<string, unknown>) => {
		if (event.error != null) {
			throw new Error(payloadErrorMessage(event, "The OpenWebUI request failed"));
		}

		responseModelID = responseModel(event, responseModelID);
		const choices = event.choices;
		if (!Array.isArray(choices)) return;
		const firstChoice = asRecord(choices[0]);
		const delta = asRecord(firstChoice?.delta);
		const streamedContent = extractStreamingText(delta?.content);
		if (streamedContent) {
			appendText(streamedContent);
			return;
		}

		const message = asRecord(firstChoice?.message);
		const completedContent = extractStreamingText(message?.content);
		if (completedContent) {
			replaceWithCompleteText(completedContent);
			return;
		}

		appendText(typeof firstChoice?.text === "string" ? firstChoice.text : "");
	};

	const result = new Promise<AIRequestResult>((resolve, reject) => {
		resolveResult = resolve;
		rejectResult = reject;

		const dataSubscription = solNative.addListener(
			"aiStreamData",
			(event: AIStreamDataEvent) => {
				if (settled || event.requestID !== requestID) return;
				if (typeof event.data !== "string") return;
				const payload = event.data.trim();
				if (!payload || payload === "[DONE]") return;

				try {
					const parsed = asRecord(JSON.parse(payload));
					if (!parsed) return;
					if (provider === "openai") {
						processOpenAIEvent(parsed);
					} else {
						processOpenWebUIEvent(parsed);
					}
				} catch (error) {
					const message =
						error instanceof SyntaxError
							? "The AI server returned an invalid streaming event"
							: error instanceof Error
								? error.message
								: "The AI streaming response failed";
					solNative.cancelAIStream(requestID);
					finishWithError(new Error(message));
				}
			},
		);
		const completedSubscription = solNative.addListener(
			"aiStreamCompleted",
			(event: AIStreamCompletedEvent) => {
				if (settled || event.requestID !== requestID) return;
				if (event.cancelled === true) {
					finishWithError(new AIStreamCancelledError());
					return;
				}
				finishSuccessfully();
			},
		);
		const failedSubscription = solNative.addListener(
			"aiStreamFailed",
			(event: AIStreamFailedEvent) => {
				if (settled || event.requestID !== requestID) return;
				finishWithError(streamFailureError(event, provider));
			},
		);

		cleanup = () => {
			if (notifyTimer) clearTimeout(notifyTimer);
			notifyTimer = null;
			dataSubscription.remove();
			completedSubscription.remove();
			failedSubscription.remove();
		};

		void solNative
			.startAIStream({ requestID, endpoint, headers, body })
			.catch((error: unknown) => {
				finishWithError(
					new Error(
						error instanceof Error
							? error.message
							: "Could not start the AI stream",
					),
				);
			});
	});

	return {
		requestID,
		result,
		cancel: () => {
			if (!settled) solNative.cancelAIStream(requestID);
		},
	};
}
