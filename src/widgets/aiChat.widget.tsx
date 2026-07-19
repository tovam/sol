import { BackButton } from "components/BackButton";
import { AIProviderModelControls } from "components/AIProviderModelControls";
import type { AIMessage } from "lib/ai";
import { solNative } from "lib/SolNative";
import { observer } from "mobx-react-lite";
import { useEffect, useRef, useState } from "react";
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

const CONVERSATION_KEY = "@sol.ai_chat_conversation";

type ChatMessage = AIMessage & { id: string };

function decodeMessage(value: unknown, fallbackID: string): ChatMessage | null {
	if (typeof value !== "object" || value === null) return null;
	const message = value as Partial<ChatMessage>;
	if (
		(message.role !== "user" && message.role !== "assistant") ||
		typeof message.content !== "string"
	) {
		return null;
	}
	return {
		id: typeof message.id === "string" ? message.id : fallbackID,
		role: message.role,
		content: message.content,
	};
}

function createMessage(role: AIMessage["role"], content: string): ChatMessage {
	return {
		id: `${Date.now()}-${Math.random().toString(36).slice(2)}`,
		role,
		content,
	};
}

export const AIChatWidget = observer(() => {
	const store = useStore();
	const scrollView = useRef<ScrollView>(null);
	const [messages, setMessages] = useState<ChatMessage[]>([]);
	const [input, setInput] = useState("");
	const [error, setError] = useState("");
	const [loading, setLoading] = useState(false);

	useEffect(() => {
		void solNative.securelyRetrieve(CONVERSATION_KEY).then((savedValue) => {
			if (!savedValue) return;
			try {
				const saved = JSON.parse(savedValue) as unknown;
				if (Array.isArray(saved)) {
					setMessages(
						saved
							.map((message, index) =>
								decodeMessage(message, `legacy-${index}`),
							)
							.filter((message): message is ChatMessage => message !== null),
					);
				}
			} catch {
				// Keep an empty conversation if a legacy value cannot be decoded.
			}
		});
	}, []);

	const persistConversation = (nextMessages: ChatMessage[]) => {
		return solNative.securelyStore(
			CONVERSATION_KEY,
			JSON.stringify(nextMessages),
		);
	};

	const clearConversation = () => {
		setMessages([]);
		setError("");
		void persistConversation([]);
	};

	const send = async () => {
		const content = input.trim();
		if (!content || loading) return;
		const messagesWithQuestion: ChatMessage[] = [
			...messages,
			createMessage("user", content),
		];
		setMessages(messagesWithQuestion);
		setInput("");
		setError("");
		setLoading(true);

		try {
			await persistConversation(messagesWithQuestion);
			const answer = await store.ai.request(
				messagesWithQuestion.map(({ role, content: messageContent }) => ({
					role,
					content: messageContent,
				})),
			);
			const completedMessages: ChatMessage[] = [
				...messagesWithQuestion,
				createMessage("assistant", answer),
			];
			setMessages(completedMessages);
			await persistConversation(completedMessages);
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
					<Text className="text-xl font-semibold text">AI Conversation</Text>
					<Text className="text-xs darker-text">
						Saved locally and ready to continue later
					</Text>
				</View>
				<AIProviderModelControls compact />
				<TouchableOpacity
					className="px-3 py-2 rounded-lg subBg border border-color"
					onPress={() => store.ui.showSettings("AI")}
				>
					<Text className="text text-sm">AI Settings</Text>
				</TouchableOpacity>
				<TouchableOpacity
					className="px-3 py-2 rounded-lg subBg border border-color"
					onPress={clearConversation}
				>
					<Text className="text text-sm">New conversation</Text>
				</TouchableOpacity>
			</View>

			<ScrollView
				ref={scrollView}
				className="flex-1 px-5 py-4"
				contentContainerStyle={{ gap: 10, paddingBottom: 16 }}
				onContentSizeChange={() => scrollView.current?.scrollToEnd()}
			>
				{messages.length === 0 && (
					<View className="flex-1 items-center justify-center py-16">
						<Text className="text-lg font-semibold text">
							Start a conversation
						</Text>
						<Text className="text-sm darker-text mt-1">
							Every answer keeps the preceding context.
						</Text>
					</View>
				)}
				{messages.map((message) => (
					<View
						key={message.id}
						className={`max-w-[85%] px-4 py-3 rounded-2xl ${
							message.role === "user"
								? "self-end bg-accent-strong"
								: "self-start subBg border border-color"
						}`}
					>
						<Text
							className={
								message.role === "user" ? "text-white" : "text leading-6"
							}
						>
							{message.content}
						</Text>
					</View>
				))}
				{loading && (
					<View className="self-start subBg border border-color px-4 py-3 rounded-2xl">
						<ActivityIndicator />
					</View>
				)}
			</ScrollView>

			{!!error && (
				<Text className="px-5 pb-2 text-sm text-red-500">{error}</Text>
			)}
			<View className="px-5 py-4 border-t border-color flex-row gap-3 items-end">
				<View className="flex-1 rounded-xl border border-color subBg px-4 py-3">
					<TextInput
						autoFocus
						multiline
						enableFocusRing={false}
						className="text-base text max-h-24"
						value={input}
						onChangeText={setInput}
						placeholder="Write a message…"
					/>
				</View>
				<TouchableOpacity
					className={`px-6 py-3 rounded-xl ${
						loading || !input.trim() ? "bg-neutral-500" : "bg-accent-strong"
					}`}
					disabled={loading || !input.trim()}
					onPress={() => void send()}
				>
					<Text className="text-white font-semibold">Send</Text>
				</TouchableOpacity>
			</View>
		</View>
	);
});
