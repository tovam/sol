import { TextInput } from "components/TextInput";
import {
	dailymotionPlayerURL,
	extractDailymotionVideoID,
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
	const [error, setError] = useState("");
	const currentVideoID = extractDailymotionVideoID(url);
	const isUpdating = store.ui.dailymotionStreams.some(
		(stream) => stream.id === currentVideoID,
	);

	const save = () => {
		if (!store.ui.saveDailymotionStream(name, url)) {
			setError("Paste a valid Dailymotion video, dai.ly, or player URL");
			return;
		}
		setError("");
		setName("");
		setURL("");
	};

	const preview = (streamURL: string) => {
		const playerURL = dailymotionPlayerURL(streamURL);
		if (!playerURL) return;
		void solNative.openDailymotionPlayer(playerURL);
	};

	return (
		<ScrollView
			className="flex-1"
			contentContainerClassName="p-5 gap-4"
			showsVerticalScrollIndicator
		>
			<View>
				<Text className="text-xl font-semibold text">Dailymotion streams</Text>
				<Text className="text-sm darker-text mt-1">
					Save videos or live streams for one-click access in the floating
					player.
				</Text>
			</View>

			<View className="rounded-xl border border-color subBg p-4 gap-3">
				<View>
					<Text className="text-xs font-semibold darker-text mb-1">Name</Text>
					<TextInput
						enableFocusRing={false}
						className="text-sm text px-3 py-2 rounded-lg border border-color"
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
						className="text-sm text px-3 py-2 rounded-lg border border-color"
						value={url}
						onChangeText={setURL}
						onSubmitEditing={save}
						placeholder="https://www.dailymotion.com/video/…"
					/>
				</View>
				{!!error && <Text className="text-sm text-red-500">{error}</Text>}
				<TouchableOpacity
					className="py-3 rounded-xl bg-accent-strong items-center"
					onPress={save}
				>
					<Text className="text-white font-semibold">
						{isUpdating ? "Update stream" : "Save stream"}
					</Text>
				</TouchableOpacity>
			</View>

			<View className="rounded-xl border border-color subBg p-4 gap-2">
				<Text className="text-sm font-semibold mb-1">
					Saved streams ({store.ui.dailymotionStreams.length})
				</Text>
				{store.ui.dailymotionStreams.length === 0 ? (
					<Text className="text-sm darker-text">No saved stream yet.</Text>
				) : (
					store.ui.dailymotionStreams.map((stream) => (
						<View
							key={stream.id}
							className="flex-row items-center gap-3 py-2 border-b border-color"
						>
							<TouchableOpacity
								className="flex-1"
								onPress={() => preview(stream.url)}
							>
								<Text className="text-sm font-medium">{stream.name}</Text>
								<Text className="text-xs darker-text" numberOfLines={1}>
									{stream.url}
								</Text>
							</TouchableOpacity>
							<TouchableOpacity
								className="px-3 py-2 rounded-lg bg-neutral-200 dark:bg-neutral-700"
								onPress={() => {
									setName(stream.name);
									setURL(stream.url);
									setError("");
								}}
							>
								<Text className="text-xs">Edit</Text>
							</TouchableOpacity>
							<TouchableOpacity
								className="px-3 py-2 rounded-lg bg-red-500/10"
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
