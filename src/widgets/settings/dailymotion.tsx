import { TextInput } from "components/TextInput";
import {
	dailymotionPlayerURL,
	extractDailymotionVideoID,
	suggestDailymotionDirectCommand,
} from "lib/dailymotion";
import { solNative } from "lib/SolNative";
import { observer } from "mobx-react-lite";
import { useState } from "react";
import { ScrollView, Text, TouchableOpacity, View } from "react-native";
import { useStore } from "store";

export const DailymotionSettings = observer(() => {
	const store = useStore();
	const [name, setName] = useState("");
	const [url, setURL] = useState("");
	const [command, setCommand] = useState("");
	const [error, setError] = useState("");
	const currentVideoID = extractDailymotionVideoID(url);
	const isUpdating = store.ui.dailymotionStreams.some(
		(stream) => stream.id === currentVideoID,
	);
	const suggestedCommand = suggestDailymotionDirectCommand(name);

	const save = () => {
		const saveError = store.ui.saveDailymotionStream(name, url, command);
		if (saveError) {
			setError(saveError);
			return;
		}
		setError("");
		setName("");
		setURL("");
		setCommand("");
	};

	const preview = (streamURL: string) => {
		const playerURL = dailymotionPlayerURL(streamURL);
		if (!playerURL) return;
		void solNative.openDailymotionPlayer(playerURL);
	};

	return (
		<ScrollView
			className="flex-1"
			contentContainerClassName="p-3 gap-2"
			showsVerticalScrollIndicator
		>
			<View className="rounded-lg border border-color subBg p-3 gap-2">
				<View>
					<Text className="text-xs font-semibold darker-text mb-1">Name</Text>
					<TextInput
						enableFocusRing={false}
						className="text-sm text px-2.5 py-1.5 rounded-md border border-color"
						value={name}
						onChangeText={setName}
						placeholder="News, music, live channel…"
					/>
				</View>
				<View>
					<Text className="text-xs font-semibold darker-text mb-1">
						Dailymotion URL
					</Text>
					<TextInput
						enableFocusRing={false}
						className="text-sm text px-2.5 py-1.5 rounded-md border border-color"
						value={url}
						onChangeText={setURL}
						onSubmitEditing={save}
						placeholder="https://www.dailymotion.com/video/…"
					/>
				</View>
				<View>
					<Text className="text-xs font-semibold darker-text mb-1">
						Direct command (optional)
					</Text>
					<View className="flex-row items-center gap-2">
						<TextInput
							enableFocusRing={false}
							autoCapitalize="none"
							autoCorrect={false}
							className="flex-1 text-sm text px-2.5 py-1.5 rounded-md border border-color"
							value={command}
							onChangeText={setCommand}
							onSubmitEditing={save}
							placeholder={suggestedCommand || "news-live"}
						/>
						<TouchableOpacity
							disabled={!suggestedCommand}
							className="px-2.5 py-1.5"
							onPress={() => setCommand(suggestedCommand)}
						>
							<Text
								className={
									suggestedCommand ? "text-sm text-accent" : "text-sm darker-text"
								}
							>
								Use name
							</Text>
						</TouchableOpacity>
					</View>
					<Text className="text-xs darker-text mt-1">
						For example, “news” opens this favorite directly; “dm{" "}
						{name.trim() || "name"}” still works.
					</Text>
				</View>
				{!!error && <Text className="text-xs text-red-500">{error}</Text>}
				<TouchableOpacity
					className="py-2 rounded-lg bg-accent-strong items-center"
					onPress={save}
				>
					<Text className="text-white font-semibold">
						{isUpdating ? "Update stream" : "Save stream"}
					</Text>
				</TouchableOpacity>
			</View>

			<View className="rounded-lg border border-color subBg p-3 gap-1.5">
				<Text className="text-sm font-semibold mb-1">
					Saved streams ({store.ui.dailymotionStreams.length})
				</Text>
				{store.ui.dailymotionStreams.length === 0 ? (
					<Text className="text-xs darker-text">No saved stream yet.</Text>
				) : (
					store.ui.dailymotionStreams.map((stream) => (
						<View
							key={stream.id}
							className="flex-row items-center gap-2 py-1.5 border-b border-color"
						>
							<TouchableOpacity
								className="flex-1"
								onPress={() => preview(stream.url)}
							>
								<Text className="text-sm font-medium">{stream.name}</Text>
								<Text className="text-xs darker-text" numberOfLines={1}>
									{stream.url}
								</Text>
								<Text className="text-xs darker-text" numberOfLines={1}>
									{stream.command
										? `Direct command: ${stream.command} · dm ${stream.name}`
										: `Command: dm ${stream.name}`}
								</Text>
							</TouchableOpacity>
							<TouchableOpacity
								className="px-2 py-1.5 rounded-md bg-neutral-200 dark:bg-neutral-700"
								onPress={() => {
									setName(stream.name);
									setURL(stream.url);
									setCommand(stream.command ?? "");
									setError("");
								}}
							>
								<Text className="text-xs">Edit</Text>
							</TouchableOpacity>
							<TouchableOpacity
								className="px-2 py-1.5 rounded-md bg-red-500/10"
								onPress={() => store.ui.removeDailymotionStream(stream.id)}
							>
								<Text className="text-xs text-red-500">Delete</Text>
							</TouchableOpacity>
						</View>
					))
				)}
			</View>
		</ScrollView>
	);
});
