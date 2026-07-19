import axios from "axios";
import { createAIHeaders, openAIEndpoint, openWebUIEndpoint } from "lib/aiHttp";
import { solNative } from "lib/SolNative";

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

const SETTINGS_KEY = "@sol.ai_one_shot_settings";

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
		return `${detail}. Check that API keys are enabled and allowed for /api/chat/completions.`;
	}
	return detail;
}

export async function loadAISettings(): Promise<AISettings> {
	const savedValue = await solNative.securelyRetrieve(SETTINGS_KEY);
	if (!savedValue) return DEFAULT_AI_SETTINGS;
	try {
		const saved = JSON.parse(savedValue) as Partial<AISettings>;
		return {
			provider: saved.provider === "openwebui" ? "openwebui" : "openai",
			openai: { ...DEFAULT_AI_SETTINGS.openai, ...saved.openai },
			openwebui: { ...DEFAULT_AI_SETTINGS.openwebui, ...saved.openwebui },
		};
	} catch {
		return DEFAULT_AI_SETTINGS;
	}
}

export function saveAISettings(settings: AISettings) {
	return solNative.securelyStore(SETTINGS_KEY, JSON.stringify(settings));
}

export async function requestAI(
	provider: AIProvider,
	settings: AIProviderSettings,
	messages: AIMessage[],
) {
	const headers = createAIHeaders(provider, settings.apiKey);

	try {
		if (provider === "openai") {
			const response = await axios.post(
				openAIEndpoint(settings.baseURL),
				{ model: settings.model.trim(), input: messages },
				{ headers },
			);
			const responseText = extractOpenAIText(response.data);
			if (!responseText) throw new Error("The API returned no text");
			return responseText;
		}

		const response = await axios.post(
			openWebUIEndpoint(settings.baseURL),
			{
				model: settings.model.trim(),
				messages,
				stream: false,
			},
			{ headers },
		);
		const responseText = extractOpenWebUIText(response.data);
		if (!responseText) throw new Error("The API returned no text");
		return responseText;
	} catch (error) {
		throw new Error(getRequestError(error, provider));
	}
}
