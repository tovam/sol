import { BackButton } from "components/BackButton";
import { observer } from "mobx-react-lite";
import { ScrollView, Text, TouchableOpacity, View } from "react-native";
import { useStore } from "store";
import type { AIConversation } from "stores/ai.store";
import { Widget } from "stores/ui.store";

function formatDate(timestamp: number) {
	return new Date(timestamp).toLocaleString();
}

function conversationPreview(conversation: AIConversation) {
	const lastMessage = conversation.messages.at(-1);
	if (!lastMessage) return "";
	const author = lastMessage.role === "user" ? "You" : "Assistant";
	return `${author}: ${lastMessage.content.replace(/\s+/g, " ").trim()}`;
}

function conversationDetails(conversation: AIConversation) {
	const messageCount = `${conversation.messages.length} message${
		conversation.messages.length === 1 ? "" : "s"
	}`;
	const provider =
		conversation.provider === "openai"
			? "OpenAI"
			: conversation.provider === "openwebui"
				? "OpenWebUI"
				: "";
	return [messageCount, provider, conversation.model].filter(Boolean).join(" · ");
}

export const AIHistoryWidget = observer(() => {
	const store = useStore();
	const conversations = store.ai.conversations;

	const openConversation = (conversationID: string) => {
		if (!store.ai.openConversation(conversationID)) return;
		store.ui.focusWidget(Widget.AI_CHAT);
	};

	const startNewConversation = () => {
		store.ai.startNewConversation();
		store.ui.focusWidget(Widget.AI_CHAT);
	};

	return (
		<View className="fullWindow">
			<View className="h-14 px-4 flex-row items-center gap-3 border-b border-color">
				<BackButton onPress={() => store.ui.focusWidget(Widget.AI_CHAT)} />
				<View className="flex-1">
					<Text className="text-lg font-semibold text">AI Conversations</Text>
					<Text className="text-xs darker-text">
						{conversations.length} saved locally
					</Text>
				</View>
				<TouchableOpacity
					className="px-3 py-1.5 rounded-lg bg-accent-strong"
					onPress={startNewConversation}
				>
					<Text className="text-white text-xs font-semibold">New chat</Text>
				</TouchableOpacity>
			</View>

			<ScrollView
				className="flex-1"
				contentContainerStyle={{ flexGrow: 1 }}
				showsVerticalScrollIndicator={false}
			>
				{conversations.length === 0 ? (
					<View className="flex-1 items-center justify-center px-6">
						<Text className="text-base font-semibold text">
							No saved conversations
						</Text>
						<Text className="text-xs darker-text mt-1 text-center">
							Your first message creates one automatically.
						</Text>
					</View>
				) : (
					conversations.map((conversation) => {
						const isActive =
							conversation.id === store.ai.activeConversationID;
						return (
							<View
								key={conversation.id}
								className={`min-h-20 px-4 flex-row items-center border-b border-color ${
									isActive ? "subBg" : ""
								}`}
							>
								<TouchableOpacity
									className="flex-1 py-3 pr-4"
									onPress={() => openConversation(conversation.id)}
								>
									<View className="flex-row items-center gap-2">
										<Text
											numberOfLines={1}
											className="flex-1 text-sm font-semibold text"
										>
											{conversation.title}
										</Text>
										<Text className="text-xs darker-text">
											{formatDate(conversation.updatedAt)}
										</Text>
									</View>
									<Text numberOfLines={1} className="text-xs darker-text mt-1">
										{conversationPreview(conversation)}
									</Text>
									<View className="flex-row items-center mt-1">
										<Text numberOfLines={1} className="flex-1 text-xs darker-text">
											{conversationDetails(conversation)}
										</Text>
										{isActive && (
											<Text className="text-xs text-accent">Open</Text>
										)}
									</View>
								</TouchableOpacity>
								<TouchableOpacity
									className="px-2 py-2"
									onPress={() => store.ai.deleteConversation(conversation.id)}
								>
									<Text className="text-xs text-red-500">Delete</Text>
								</TouchableOpacity>
							</View>
						);
					})
				)}
			</ScrollView>
		</View>
	);
});
