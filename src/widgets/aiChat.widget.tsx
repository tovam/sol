import { BackButton } from "components/BackButton";
import { AIProviderModelControls } from "components/AIProviderModelControls";
import type { AIMessage } from "lib/ai";
import { observer } from "mobx-react-lite";
import { useRef, useState } from "react";
import {
	ActivityIndicator,
	ScrollView,
	Text,
	TouchableOpacity,
	View,
} from "react-native";
import { TextInput } from "react-native-macos";
import { useStore } from "store";
import { Widget } from "stores/ui.store";

function createMessage(role: AIMessage["role"], content: string): AIMessage {
	return { role, content };
}

export const AIChatWidget = observer(() => {
	const store = useStore();
	const scrollView = useRef<ScrollView>(null);
	const [input, setInput] = useState("");
	const [error, setError] = useState("");
	const [loading, setLoading] = useState(false);

	const messages = store.ai.conversation;

	const clearConversation = () => {
		store.ai.setConversation([]);
		setError("");
	};

	const send = async () => {
		const content = input.trim();
		if (!content || loading) return;
		const messagesWithQuestion: AIMessage[] = [
			...messages,
			createMessage("user", content),
		];
		store.ai.setConversation(messagesWithQuestion);
		setInput("");
		setError("");
		setLoading(true);

		try {
			const answer = await store.ai.request(
				messagesWithQuestion.map(({ role, content: messageContent }) => ({
					role,
					content: messageContent,
				})),
			);
			const completedMessages: AIMessage[] = [
				...messagesWithQuestion,
				createMessage("assistant", answer),
			];
			store.ai.setConversation(completedMessages);
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
					<Text className="text-lg font-semibold text">AI Chat</Text>
					<Text className="text-xs darker-text">saved locally</Text>
				</View>
				<AIProviderModelControls compact />
				<TouchableOpacity
					className="px-2.5 py-1.5 rounded-lg subBg border border-color"
					onPress={() => store.ui.showSettings("AI")}
				>
					<Text className="text text-xs">Settings</Text>
				</TouchableOpacity>
				<TouchableOpacity
					disabled={loading}
					className={`px-2.5 py-1.5 rounded-lg subBg border border-color ${
						loading ? "opacity-50" : ""
					}`}
					onPress={clearConversation}
				>
					<Text className="text text-xs">New</Text>
				</TouchableOpacity>
			</View>

			<ScrollView
				ref={scrollView}
				className="flex-1 px-4 py-3"
				contentContainerStyle={{ flexGrow: 1, gap: 8, paddingBottom: 12 }}
				onContentSizeChange={() => scrollView.current?.scrollToEnd()}
			>
				{messages.length === 0 && (
					<View className="flex-1 items-center justify-center py-12">
						<Text className="text-base font-semibold text">
							Start a conversation
						</Text>
						<Text className="text-xs darker-text mt-1">
							Every answer keeps the preceding context.
						</Text>
					</View>
				)}
				{messages.map((message, index) => (
					<View
						key={`${message.role}-${index}`}
						className={`max-w-[84%] px-3 py-2 rounded-lg ${
							message.role === "user"
								? "self-end bg-accent-strong"
								: "self-start subBg border border-color"
						}`}
					>
						<Text
							selectable
							className={
								message.role === "user"
									? "text-white text-sm"
									: "text text-sm leading-5"
							}
						>
							{message.content}
						</Text>
					</View>
				))}
				{loading && (
					<View className="self-start subBg border border-color px-3 py-2 rounded-lg flex-row items-center gap-2">
						<ActivityIndicator size="small" />
						<Text className="text-xs darker-text">Thinking…</Text>
					</View>
				)}
			</ScrollView>

			{!!error && (
				<Text className="px-4 pb-1 text-xs text-red-500">{error}</Text>
			)}
			<View className="px-4 py-3 border-t border-color flex-row gap-2 items-end">
				<View className="flex-1 rounded-lg border border-color subBg px-3 py-2">
					<TextInput
						autoFocus
						multiline
						enableFocusRing={false}
						className="text-sm text max-h-20"
						value={input}
						onChangeText={setInput}
						placeholder="Write a message…"
					/>
				</View>
				<TouchableOpacity
					className={`px-4 py-2 rounded-lg ${
						loading || !input.trim() ? "bg-neutral-500" : "bg-accent-strong"
					}`}
					disabled={loading || !input.trim()}
					onPress={() => void send()}
				>
					<Text className="text-white text-sm font-semibold">Send</Text>
				</TouchableOpacity>
			</View>
		</View>
	);
});
