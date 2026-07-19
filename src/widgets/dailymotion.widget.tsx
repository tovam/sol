import { BackButton } from "components/BackButton";
import {
	dailymotionEmbedURL,
	extractDailymotionVideoID,
} from "lib/dailymotion";
import { solNative } from "lib/SolNative";
import { type FC, useEffect, useState } from "react";
import { Clipboard, Text, TouchableOpacity, View } from "react-native";
import { TextInput } from "react-native-macos";
import { useStore } from "store";
import { Widget } from "stores/ui.store";

export const DailymotionWidget: FC = () => {
	const store = useStore();
	const [url, setURL] = useState("");
	const [error, setError] = useState("");

	useEffect(() => {
		void Clipboard.getString().then((clipboardText) => {
			if (extractDailymotionVideoID(clipboardText)) {
				setURL(clipboardText.trim());
			}
		});
	}, []);

	const openPlayer = () => {
		const videoID = extractDailymotionVideoID(url);
		if (!videoID) {
			setError("Paste a Dailymotion video or dai.ly URL");
			return;
		}
		setError("");
		solNative.openDailymotionPlayer(dailymotionEmbedURL(videoID));
		void solNative.showToast("Floating player opened", "success");
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
					<Text className="text-xl font-semibold text">Dailymotion Player</Text>
					<Text className="text-xs darker-text">
						Always on top, resizable, and visible on every Space
					</Text>
				</View>
			</View>

			<View className="flex-1 px-10 py-8 gap-5">
				<View className="rounded-2xl border border-color subBg p-5 gap-2">
					<Text className="text-xs font-semibold darker-text">VIDEO URL</Text>
					<TextInput
						autoFocus
						enableFocusRing={false}
						className="text-base text"
						value={url}
						onChangeText={setURL}
						onSubmitEditing={openPlayer}
						placeholder="https://www.dailymotion.com/video/…"
					/>
				</View>

				{!!error && <Text className="text-sm text-red-500">{error}</Text>}

				<View className="flex-row gap-3">
					<View className="flex-1 rounded-xl border border-color p-4">
						<Text className="text-2xl">▣</Text>
						<Text className="text font-semibold mt-2">16:9 player</Text>
						<Text className="text-xs darker-text mt-1">Resize it freely</Text>
					</View>
					<View className="flex-1 rounded-xl border border-color p-4">
						<Text className="text-2xl">⌃</Text>
						<Text className="text font-semibold mt-2">Always visible</Text>
						<Text className="text-xs darker-text mt-1">
							Floats above other apps
						</Text>
					</View>
					<View className="flex-1 rounded-xl border border-color p-4">
						<Text className="text-2xl">◫</Text>
						<Text className="text font-semibold mt-2">All Spaces</Text>
						<Text className="text-xs darker-text mt-1">
							Follows your desktop
						</Text>
					</View>
				</View>

				<TouchableOpacity
					className="mt-auto py-4 rounded-xl bg-accent-strong items-center"
					onPress={openPlayer}
				>
					<Text className="text-white font-semibold">Open floating player</Text>
				</TouchableOpacity>
			</View>
		</View>
	);
};
