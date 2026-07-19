import {
	type AIProvider,
	type AIProviderSettings,
	type AISettings,
	DEFAULT_AI_SETTINGS,
	loadAISettings,
	requestAI,
	saveAISettings,
} from "lib/ai";
import { useEffect, useState } from "react";
import {
	ActivityIndicator,
	ScrollView,
	Text,
	TouchableOpacity,
	View,
} from "react-native";
import { TextInput } from "react-native-macos";

type TestState = "idle" | "testing" | "success" | "error";

function validationError(
	provider: AIProvider,
	settings: AIProviderSettings,
): string | null {
	if (!settings.baseURL.trim()) return "Enter the API server URL";
	if (!settings.model.trim()) return "Enter a model name";
	if (provider === "openai" && !settings.apiKey.trim()) {
		return "Enter your OpenAI API key";
	}
	return null;
}

export function AI() {
	const [settings, setSettings] = useState<AISettings>(DEFAULT_AI_SETTINGS);
	const [loading, setLoading] = useState(true);
	const [saving, setSaving] = useState(false);
	const [testState, setTestState] = useState<TestState>("idle");
	const [message, setMessage] = useState("");

	useEffect(() => {
		void loadAISettings().then((loadedSettings) => {
			setSettings(loadedSettings);
			setLoading(false);
		});
	}, []);

	const current = settings[settings.provider];

	const selectProvider = (provider: AIProvider) => {
		setSettings((previous) => ({ ...previous, provider }));
		setTestState("idle");
		setMessage("");
	};

	const updateCurrent = (key: keyof AIProviderSettings, value: string) => {
		setSettings((previous) => ({
			...previous,
			[previous.provider]: {
				...previous[previous.provider],
				[key]: value,
			},
		}));
		setTestState("idle");
		setMessage("");
	};

	const save = async () => {
		setSaving(true);
		setMessage("");
		try {
			await saveAISettings(settings);
			setMessage("Saved securely in the macOS Keychain");
		} catch (error) {
			setMessage(
				error instanceof Error ? error.message : "Could not save settings",
			);
		} finally {
			setSaving(false);
		}
	};

	const testConnection = async () => {
		const invalid = validationError(settings.provider, current);
		if (invalid) {
			setTestState("error");
			setMessage(invalid);
			return;
		}

		setTestState("testing");
		setMessage("");
		try {
			await saveAISettings(settings);
			const response = await requestAI(settings.provider, current, [
				{ role: "user", content: "Reply with exactly: OK" },
			]);
			setTestState("success");
			setMessage(`Connected — ${response.trim().slice(0, 120)}`);
		} catch (error) {
			setTestState("error");
			setMessage(error instanceof Error ? error.message : "Connection failed");
		}
	};

	if (loading) {
		return (
			<View className="flex-1 items-center justify-center">
				<ActivityIndicator />
			</View>
		);
	}

	return (
		<ScrollView
			className="flex-1"
			contentContainerClassName="p-5 gap-4"
			showsVerticalScrollIndicator
		>
			<View>
				<Text className="text-xl font-semibold text">
					Artificial intelligence
				</Text>
				<Text className="text-sm darker-text mt-1">
					One configuration is shared by Ask AI and AI Conversation.
				</Text>
			</View>

			<View className="flex-row gap-2">
				{(["openai", "openwebui"] as const).map((provider) => (
					<TouchableOpacity
						key={provider}
						className={`flex-1 py-3 rounded-lg border items-center ${
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

			<View className="rounded-xl border border-color subBg p-4 gap-4">
				<View>
					<Text className="text-xs font-semibold darker-text mb-1">
						API server
					</Text>
					<TextInput
						enableFocusRing={false}
						className="text-sm text px-3 py-2 rounded-lg border border-color"
						value={current.baseURL}
						onChangeText={(value) => updateCurrent("baseURL", value)}
						placeholder={
							settings.provider === "openai"
								? "https://api.openai.com/v1"
								: "http://localhost:3000"
						}
					/>
				</View>

				<View>
					<Text className="text-xs font-semibold darker-text mb-1">Model</Text>
					<TextInput
						enableFocusRing={false}
						className="text-sm text px-3 py-2 rounded-lg border border-color"
						value={current.model}
						onChangeText={(value) => updateCurrent("model", value)}
						placeholder={
							settings.provider === "openai" ? "gpt-5.6-sol" : "llama3.2"
						}
					/>
				</View>

				<View>
					<Text className="text-xs font-semibold darker-text mb-1">
						API key{settings.provider === "openwebui" ? " (optional)" : ""}
					</Text>
					<TextInput
						enableFocusRing={false}
						secureTextEntry
						className="text-sm text px-3 py-2 rounded-lg border border-color"
						value={current.apiKey}
						onChangeText={(value) => updateCurrent("apiKey", value)}
						placeholder="Stored in Keychain"
					/>
				</View>
			</View>

			{!!message && (
				<Text
					className={
						testState === "error"
							? "text-sm text-red-500"
							: testState === "success"
								? "text-sm text-green-600 dark:text-green-400"
								: "text-sm darker-text"
					}
				>
					{message}
				</Text>
			)}

			<View className="flex-row gap-3">
				<TouchableOpacity
					className="flex-1 py-3 rounded-xl items-center border border-color subBg"
					disabled={saving || testState === "testing"}
					onPress={() => void save()}
				>
					{saving ? <ActivityIndicator /> : <Text className="text">Save</Text>}
				</TouchableOpacity>
				<TouchableOpacity
					className="flex-1 py-3 rounded-xl items-center bg-accent-strong"
					disabled={saving || testState === "testing"}
					onPress={() => void testConnection()}
				>
					{testState === "testing" ? (
						<ActivityIndicator color="white" />
					) : (
						<Text className="text-white font-semibold">Test connection</Text>
					)}
				</TouchableOpacity>
			</View>
			<Text className="text-xs darker-text">
				The URL, model and API keys are stored locally in the macOS Keychain.
			</Text>
		</ScrollView>
	);
}
