import axios from "axios";
import { BackButton } from "components/BackButton";
import { solNative } from "lib/SolNative";
import { type FC, useEffect, useState } from "react";
import {
	ActivityIndicator,
	Clipboard,
	ScrollView,
	Text,
	TouchableOpacity,
	View,
} from "react-native";
import { TextInput } from "react-native-macos";
import { useStore } from "store";
import { Widget } from "stores/ui.store";

type Provider = "openai" | "openwebui";

type ProviderSettings = {
	baseURL: string;
	model: string;
	apiKey: string;
};

type Settings = {
	provider: Provider;
	openai: ProviderSettings;
	openwebui: ProviderSettings;
};

const SETTINGS_KEY = "@sol.ai_one_shot_settings";
const DEFAULT_SETTINGS: Settings = {
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

function trimTrailingSlashes(value: string) {
	return value.trim().replace(/\/+$/, "");
}

function openAIEndpoint(baseURL: string) {
	const base = trimTrailingSlashes(baseURL);
	if (base.endsWith("/responses")) return base;
	if (base.endsWith("/v1")) return `${base}/responses`;
	return `${base}/v1/responses`;
}

function openWebUIEndpoint(baseURL: string) {
	const base = trimTrailingSlashes(baseURL);
	if (base.endsWith("/api/chat/completions")) return base;
	if (base.endsWith("/api")) return `${base}/chat/completions`;
	return `${base}/api/chat/completions`;
}

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

function getRequestError(error: unknown) {
	if (!axios.isAxiosError(error)) return "The request failed";
	const data = asRecord(error.response?.data);
	const apiError = asRecord(data?.error);
	if (typeof apiError?.message === "string") return apiError.message;
	if (typeof data?.detail === "string") return data.detail;
	return error.message;
}

export const AIOneShotWidget: FC = () => {
	const store = useStore();
	const [settings, setSettings] = useState<Settings>(DEFAULT_SETTINGS);
	const [question, setQuestion] = useState("");
	const [answer, setAnswer] = useState("");
	const [error, setError] = useState("");
	const [loading, setLoading] = useState(false);

	useEffect(() => {
		void solNative.securelyRetrieve(SETTINGS_KEY).then((savedValue) => {
			if (!savedValue) return;
			try {
				const saved = JSON.parse(savedValue) as Partial<Settings>;
				setSettings({
					provider: saved.provider === "openwebui" ? "openwebui" : "openai",
					openai: { ...DEFAULT_SETTINGS.openai, ...saved.openai },
					openwebui: { ...DEFAULT_SETTINGS.openwebui, ...saved.openwebui },
				});
			} catch {
				// Ignore an invalid legacy value and retain safe defaults.
			}
		});
	}, []);

	const current = settings[settings.provider];

	const saveSettings = async (nextSettings = settings) => {
		await solNative.securelyStore(SETTINGS_KEY, JSON.stringify(nextSettings));
	};

	const selectProvider = (provider: Provider) => {
		const nextSettings = { ...settings, provider };
		setSettings(nextSettings);
		void saveSettings(nextSettings);
		setError("");
		setAnswer("");
	};

	const updateCurrent = (key: keyof ProviderSettings, value: string) => {
		setSettings((previous) => ({
			...previous,
			[previous.provider]: {
				...previous[previous.provider],
				[key]: value,
			},
		}));
	};

	const ask = async () => {
		const prompt = question.trim();
		if (!prompt) {
			setError("Write a question first");
			return;
		}
		if (!current.baseURL.trim()) {
			setError("Enter the API server URL");
			return;
		}
		if (!current.model.trim()) {
			setError("Enter a model name");
			return;
		}
		if (settings.provider === "openai" && !current.apiKey.trim()) {
			setError("Enter your OpenAI API key");
			return;
		}

		setLoading(true);
		setError("");
		setAnswer("");
		try {
			await saveSettings();
			const headers: Record<string, string> = {
				"Content-Type": "application/json",
			};
			if (current.apiKey.trim()) {
				headers.Authorization = `Bearer ${current.apiKey.trim()}`;
			}

			if (settings.provider === "openai") {
				const response = await axios.post(
					openAIEndpoint(current.baseURL),
					{ model: current.model.trim(), input: prompt },
					{ headers },
				);
				const responseText = extractOpenAIText(response.data);
				if (!responseText) throw new Error("The API returned no text");
				setAnswer(responseText);
			} else {
				const response = await axios.post(
					openWebUIEndpoint(current.baseURL),
					{
						model: current.model.trim(),
						messages: [{ role: "user", content: prompt }],
						stream: false,
					},
					{ headers },
				);
				const responseText = extractOpenWebUIText(response.data);
				if (!responseText) throw new Error("The API returned no text");
				setAnswer(responseText);
			}
		} catch (requestError) {
			setError(
				requestError instanceof Error && !axios.isAxiosError(requestError)
					? requestError.message
					: getRequestError(requestError),
			);
		} finally {
			setLoading(false);
		}
	};

	return (
		<View className="fullWindow">
			<View className="h-16 px-5 flex-row items-center gap-3 border-b border-color">
				<BackButton
					onPress={() => {
						store.ui.setQuery("");
						store.ui.focusWidget(Widget.SEARCH);
					}}
				/>
				<View className="flex-1">
					<Text className="text-xl font-semibold text">Ask AI</Text>
					<Text className="text-xs darker-text">
						One question, one answer — no conversation history
					</Text>
				</View>
			</View>

			<View className="flex-1 px-6 py-5 gap-4">
				<View className="flex-row gap-2">
					{(["openai", "openwebui"] as const).map((provider) => (
						<TouchableOpacity
							key={provider}
							className={`flex-1 py-2 rounded-lg border items-center ${
								settings.provider === provider
									? "bg-accent-strong border-transparent"
									: "subBg border-color"
							}`}
							onPress={() => selectProvider(provider)}
						>
							<Text
								className={
									settings.provider === provider
										? "text-white font-semibold"
										: "text"
								}
							>
								{provider === "openai" ? "OpenAI" : "OpenWebUI"}
							</Text>
						</TouchableOpacity>
					))}
				</View>

				<View className="flex-row gap-3">
					<View className="flex-[2] rounded-xl border border-color subBg px-3 py-2">
						<Text className="text-xs darker-text">API server</Text>
						<TextInput
							enableFocusRing={false}
							className="text-sm text mt-1"
							value={current.baseURL}
							onChangeText={(value) => updateCurrent("baseURL", value)}
						/>
					</View>
					<View className="flex-1 rounded-xl border border-color subBg px-3 py-2">
						<Text className="text-xs darker-text">Model</Text>
						<TextInput
							enableFocusRing={false}
							className="text-sm text mt-1"
							value={current.model}
							onChangeText={(value) => updateCurrent("model", value)}
							placeholder={
								settings.provider === "openai" ? "gpt-5.6-sol" : "llama3.2"
							}
						/>
					</View>
					<View className="flex-1 rounded-xl border border-color subBg px-3 py-2">
						<Text className="text-xs darker-text">
							API key{settings.provider === "openwebui" ? " (optional)" : ""}
						</Text>
						<TextInput
							enableFocusRing={false}
							secureTextEntry
							className="text-sm text mt-1"
							value={current.apiKey}
							onChangeText={(value) => updateCurrent("apiKey", value)}
							placeholder="Stored in Keychain"
						/>
					</View>
				</View>

				<View className="flex-1 flex-row gap-4">
					<View className="flex-1 rounded-xl border border-color subBg p-4">
						<Text className="text-xs font-semibold darker-text mb-2">
							QUESTION
						</Text>
						<TextInput
							autoFocus
							multiline
							enableFocusRing={false}
							className="flex-1 text-base text"
							value={question}
							onChangeText={setQuestion}
							placeholder="What do you want to know?"
							textAlignVertical="top"
						/>
					</View>

					<View className="flex-1 rounded-xl border border-color subBg p-4">
						<View className="flex-row items-center mb-2">
							<Text className="flex-1 text-xs font-semibold darker-text">
								ANSWER
							</Text>
							{!!answer && (
								<TouchableOpacity
									onPress={() => {
										Clipboard.setString(answer);
										void solNative.showToast("Answer copied", "success");
									}}
								>
									<Text className="text-xs text-accent">Copy</Text>
								</TouchableOpacity>
							)}
						</View>
						<ScrollView className="flex-1">
							<Text className="text-base text leading-6">
								{answer || "The answer will appear here."}
							</Text>
						</ScrollView>
					</View>
				</View>

				{!!error && <Text className="text-sm text-red-500">{error}</Text>}
				<TouchableOpacity
					className={`py-3 rounded-xl items-center ${
						loading ? "bg-neutral-500" : "bg-accent-strong"
					}`}
					disabled={loading}
					onPress={() => void ask()}
				>
					{loading ? (
						<ActivityIndicator color="white" />
					) : (
						<Text className="text-white font-semibold">Ask</Text>
					)}
				</TouchableOpacity>
			</View>
		</View>
	);
};
