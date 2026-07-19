import { BackButton } from "components/BackButton";
import { AIProviderModelControls } from "components/AIProviderModelControls";
import { solNative } from "lib/SolNative";
import { observer } from "mobx-react-lite";
import { useEffect, useRef, useState } from "react";
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
	const askRef = useRef<() => void>(() => undefined);

	const ask = async () => {
		const prompt = question.trim();
		if (loading) return;
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

	askRef.current = () => void ask();

	useEffect(() => {
		solNative.turnOffEnterListener();
		const subscription = solNative.addListener("keyDown", (event) => {
			if (event.keyCode === 36 && event.meta && !event.shift) {
				askRef.current();
			}
		});
		return () => {
			subscription.remove();
			solNative.turnOnEnterListener();
		};
	}, []);

	return (
		<View className="fullWindow">
			<View
				className="h-14 px-4 flex-row items-center gap-2 border-b border-color"
				style={{ zIndex: 20 }}
			>
				<BackButton
					onPress={() => {
						store.ui.setQuery("");
						store.ui.focusWidget(Widget.SEARCH);
					}}
				/>
				<View className="flex-1 flex-row items-center gap-2">
					<Text className="text-lg font-semibold text">Ask AI</Text>
					<Text className="text-xs darker-text">one-shot</Text>
				</View>
				<AIProviderModelControls compact />
				<TouchableOpacity
					className="px-2.5 py-1.5 rounded-lg subBg border border-color"
					onPress={() => store.ui.showSettings("AI")}
				>
					<Text className="text text-xs">Settings</Text>
				</TouchableOpacity>
			</View>

			<View className="flex-1 px-4 py-3 gap-2">
				<View className="flex-row items-center px-1">
					<Text className="flex-1 text-xs font-semibold darker-text">
						Response
					</Text>
					{!!answer && !loading && (
						<TouchableOpacity
							className="px-2 py-1"
							onPress={() => {
								Clipboard.setString(answer);
								void solNative.showToast("Answer copied", "success");
							}}
						>
							<Text className="text-xs text-accent">Copy</Text>
						</TouchableOpacity>
					)}
				</View>
				<View className="flex-1 rounded-lg border border-color subBg overflow-hidden">
					<ScrollView
						className="flex-1"
						contentContainerStyle={
							answer
								? { padding: 14 }
								: {
										flexGrow: 1,
										alignItems: "center",
										justifyContent: "center",
										padding: 14,
									}
						}
					>
						{loading ? (
							<View className="items-center gap-2">
								<ActivityIndicator />
								<Text className="text-xs darker-text">Thinking…</Text>
							</View>
						) : (
							<Text
								selectable
								className={answer ? "text-sm text leading-5" : "text-sm darker-text"}
							>
								{answer || "Your answer will appear here."}
							</Text>
						)}
					</ScrollView>
				</View>

				{!!error && <Text className="text-sm text-red-500">{error}</Text>}
				<View className="flex-row gap-2 items-end">
					<View className="flex-1 rounded-lg border border-color subBg px-3 py-2">
						<TextInput
							autoFocus
							multiline
							enableFocusRing={false}
							className="text-sm text max-h-20"
							value={question}
							onChangeText={setQuestion}
							placeholder="Ask a question…"
						/>
					</View>
					<TouchableOpacity
						className={`px-4 py-2 rounded-lg items-center ${
							loading || !question.trim()
								? "bg-neutral-500"
								: "bg-accent-strong"
						}`}
						disabled={loading || !question.trim()}
						onPress={() => void ask()}
					>
						<Text className="text-white text-sm font-semibold">Ask  ⌘↩</Text>
					</TouchableOpacity>
				</View>
			</View>
		</View>
	);
});
