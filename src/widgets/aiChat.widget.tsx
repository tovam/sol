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

function createMessage(role: AIMessage["role"], content: string): AIMessage {
	return { role, content };
}

export const AIChatWidget = observer(() => {
	const store = useStore();
	const scrollView = useRef<ScrollView>(null);
	const [input, setInput] = useState("");
	const [error, setError] = useState("");
	const [loading, setLoading] = useState(false);
	const sendRef = useRef<() => void>(() => undefined);
	const submittingRef = useRef(false);

	const messages = store.ai.conversation;
	const activeConversationPending = store.ai.activeConversationID
		? store.ai.isConversationPending(store.ai.activeConversationID)
		: false;
	const isConversationLoading = loading || activeConversationPending;

	const newConversation = () => {
		store.ai.startNewConversation();
		setError("");
	};

	const send = async () => {
		const content = input.trim();
		if (!content || submittingRef.current) return;
		if (
			store.ai.activeConversationID &&
			store.ai.isConversationPending(store.ai.activeConversationID)
		) {
			return;
		}
		submittingRef.current = true;
		const messagesWithQuestion: AIMessage[] = [
			...messages,
			createMessage("user", content),
		];
		const conversationID =
			store.ai.saveCurrentConversation(messagesWithQuestion);
		if (conversationID) store.ai.setConversationPending(conversationID, true);
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
			if (conversationID) {
				store.ai.updateConversation(conversationID, completedMessages);
			}
		} catch (requestError) {
			setError(
				requestError instanceof Error
					? requestError.message
					: "The request failed",
			);
		} finally {
			if (conversationID) store.ai.setConversationPending(conversationID, false);
			submittingRef.current = false;
			setLoading(false);
		}
	};

	sendRef.current = () => void send();

	useEffect(() => {
		solNative.turnOffEnterListener();
		solNative.turnOnCommandEnterListener();
		const subscription = solNative.addListener("keyDown", (event) => {
			if (event.keyCode === 36 && event.meta && !event.shift) {
				sendRef.current();
			}
		});
		return () => {
			subscription.remove();
			solNative.turnOffCommandEnterListener();
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
					<Text className="text-lg font-semibold text">AI Chat</Text>
					<Text className="text-xs darker-text">saved locally</Text>
				</View>
				<AIProviderModelControls compact />
				<TouchableOpacity
					className="px-2.5 py-1.5 rounded-lg subBg border border-color"
					onPress={() => store.ui.openAIHistory()}
				>
					<Text className="text text-xs">
						History ({store.ai.conversations.length})
					</Text>
				</TouchableOpacity>
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
					onPress={newConversation}
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
				{isConversationLoading && (
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
						isConversationLoading || !input.trim()
							? "bg-neutral-500"
							: "bg-accent-strong"
					}`}
					disabled={isConversationLoading || !input.trim()}
					onPress={() => void send()}
				>
					<Text className="text-white text-sm font-semibold">Send  ⌘↩</Text>
				</TouchableOpacity>
			</View>
		</View>
	);
});
