import { BackButton } from "components/BackButton";
import { AIProviderModelControls } from "components/AIProviderModelControls";
import { solNative } from "lib/SolNative";
import { observer } from "mobx-react-lite";
import { useState } from "react";
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

export const AIOneShotWidget = observer(() => {
	const store = useStore();
	const [question, setQuestion] = useState("");
	const [answer, setAnswer] = useState("");
	const [error, setError] = useState("");
	const [loading, setLoading] = useState(false);

	const ask = async () => {
		const prompt = question.trim();
		if (!prompt) {
			setError("Write a question first");
			return;
		}
		setLoading(true);
		setError("");
		setAnswer("");
		try {
			const responseText = await store.ai.request([
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
				<AIProviderModelControls compact />
				<TouchableOpacity
					className="px-3 py-2 rounded-lg subBg border border-color"
					onPress={() => store.ui.showSettings("AI")}
				>
					<Text className="text text-sm">AI Settings</Text>
				</TouchableOpacity>
			</View>

			<View className="flex-1 px-6 py-5 gap-4">
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
});
