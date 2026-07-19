import { BackButton } from "components/BackButton";
import {
	DEFAULT_AI_SETTINGS,
	loadAISettings,
	type AIProvider as Provider,
	type AIProviderSettings as ProviderSettings,
	requestAI,
	type AISettings as Settings,
	saveAISettings,
} from "lib/ai";
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

export const AIOneShotWidget: FC = () => {
	const store = useStore();
	const [settings, setSettings] = useState<Settings>(DEFAULT_AI_SETTINGS);
	const [question, setQuestion] = useState("");
	const [answer, setAnswer] = useState("");
	const [error, setError] = useState("");
	const [loading, setLoading] = useState(false);

	useEffect(() => {
		void loadAISettings().then(setSettings);
	}, []);

	const current = settings[settings.provider];

	const saveSettings = async (nextSettings = settings) => {
		await saveAISettings(nextSettings);
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
			const responseText = await requestAI(settings.provider, current, [
				{ role: "user", content: prompt },
			]);
			setAnswer(responseText);
		} catch (requestError) {
			setError(
				requestError instanceof Error
					? requestError.message
					: "The request failed",
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
