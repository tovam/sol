import { AIProviderModelControls } from "components/AIProviderModelControls";
import { OpenAICostSummary } from "components/OpenAICostSummary";
import { TextInput } from "components/TextInput";
import type { AIProviderSettings } from "lib/ai";
import { observer } from "mobx-react-lite";
import { useState } from "react";
import {
	ActivityIndicator,
	ScrollView,
	Text,
	TouchableOpacity,
	View,
} from "react-native";
import { useStore } from "store";
import { validateAIProviderSettings } from "stores/ai.store";

type TestState = "idle" | "testing" | "success" | "error";

export const AI = observer(() => {
	const { ai } = useStore();
	const [saving, setSaving] = useState(false);
	const [testState, setTestState] = useState<TestState>("idle");
	const [message, setMessage] = useState("");
	const [editingAPIKey, setEditingAPIKey] = useState(false);
	const busy = saving || testState === "testing" || ai.secretsLoading;

	const settings = ai.settings;
	const current = settings[settings.provider];

	const resetTestState = () => {
		setEditingAPIKey(false);
		setTestState("idle");
		setMessage("");
	};

	const updateCurrent = (key: keyof AIProviderSettings, value: string) => {
		ai.updateProviderSettings(settings.provider, key, value);
		setTestState("idle");
		setMessage("");
	};

	const save = async () => {
		setSaving(true);
		setMessage("");
		try {
			await ai.saveSecureSettings();
			setMessage("Saved locally without using macOS Keychain");
		} catch (error) {
			setMessage(
				error instanceof Error ? error.message : "Could not save settings",
			);
		} finally {
			setSaving(false);
		}
	};

	const testConnection = async () => {
		setTestState("testing");
		setMessage("");
		await ai.ensureSecretsLoaded();
		const provider = ai.settings.provider;
		const providerSettings = ai.settings[provider];
		const invalid = validateAIProviderSettings(provider, providerSettings);
		if (invalid) {
			setTestState("error");
			setMessage(invalid);
			return;
		}

		try {
			const response = await ai.request([
				{ role: "user", content: "Reply with exactly: OK" },
			]);
			setTestState("success");
			setMessage(`Connected — ${response.trim().slice(0, 120)}`);
		} catch (error) {
			setTestState("error");
			setMessage(error instanceof Error ? error.message : "Connection failed");
		}
	};

	if (!ai.initialized) {
		return (
			<View className="flex-1 items-center justify-center">
				<ActivityIndicator />
			</View>
		);
	}

	return (
		<ScrollView
			className="flex-1"
			contentContainerClassName="p-3 gap-2"
			showsVerticalScrollIndicator
		>
			<AIProviderModelControls
				compact
				fluid
				disabled={busy}
				onSelectionChange={resetTestState}
			/>
			<OpenAICostSummary />

			<View className="rounded-lg border border-color subBg p-3 gap-2.5">
				<View>
					<Text className="text-xs font-semibold darker-text mb-1">
						API server
					</Text>
					<TextInput
						enableFocusRing={false}
						editable={!busy}
						className="text-sm text px-2.5 py-1.5 rounded-md border border-color"
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
						editable={!busy}
						className="text-sm text px-2.5 py-1.5 rounded-md border border-color"
						value={current.model}
						onChangeText={(value) => updateCurrent("model", value)}
						placeholder={
							settings.provider === "openai" ? "gpt-5.6-sol" : "llama3.2"
						}
					/>
					<Text className="text-xs darker-text mt-1">
						Manual model ID, useful for proxies or models hidden by the text
						filter.
					</Text>
				</View>

				<View>
					<View className="flex-row items-center mb-1">
						<Text className="flex-1 text-xs font-semibold darker-text">
							API key{settings.provider === "openwebui" ? " (optional)" : ""}
						</Text>
						{!!current.apiKey && !editingAPIKey && (
							<Text className="text-xs darker-text">
								{current.apiKey.length} characters
							</Text>
						)}
					</View>

					{editingAPIKey ? (
						<View className="flex-row items-center gap-2">
							<TextInput
								autoFocus
								enableFocusRing={false}
								editable={!busy}
								autoCapitalize="none"
								autoCorrect={false}
								spellCheck={false}
								className="flex-1 text-sm text px-2.5 py-1.5 rounded-md border border-color"
								value={current.apiKey}
								onChangeText={(value) => updateCurrent("apiKey", value)}
								onSubmitEditing={() => setEditingAPIKey(false)}
								placeholder="Paste the API key"
							/>
							<TouchableOpacity
								disabled={busy}
								className="px-2.5 py-1.5"
								onPress={() => setEditingAPIKey(false)}
							>
								<Text className="text-sm text-accent">Done</Text>
							</TouchableOpacity>
						</View>
					) : (
						<TouchableOpacity
							disabled={busy}
							className="px-2.5 py-1.5 rounded-md border border-color flex-row items-center"
							onPress={() => setEditingAPIKey(true)}
						>
							<Text className="flex-1 text-sm darker-text">
								{current.apiKey ? "••••••••••••" : "No API key configured"}
							</Text>
							<Text className="text-sm text-accent">
								{current.apiKey ? "Replace" : "Add"}
							</Text>
						</TouchableOpacity>
					)}
				</View>
			</View>

			{!!message && (
				<Text
					className={
						testState === "error"
							? "text-xs text-red-500"
							: testState === "success"
								? "text-xs text-green-600 dark:text-green-400"
								: "text-xs darker-text"
					}
				>
					{message}
				</Text>
			)}

			<View className="flex-row gap-2">
				<TouchableOpacity
					className="flex-1 py-2 rounded-lg items-center border border-color subBg"
					disabled={saving || testState === "testing"}
					onPress={() => void save()}
				>
					{saving ? <ActivityIndicator /> : <Text className="text">Save</Text>}
				</TouchableOpacity>
				<TouchableOpacity
					className="flex-1 py-2 rounded-lg items-center bg-accent-strong"
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
				API keys are stored separately in a private file readable only by your
				macOS user. Sol never asks Keychain for them.
			</Text>
		</ScrollView>
	);
});
