import { BackButton } from "components/BackButton";
import {
	dailymotionPlayerURL,
	extractDailymotionVideoID,
} from "lib/dailymotion";
import { solNative } from "lib/SolNative";
import { type FC, useEffect, useState } from "react";
import {
	Clipboard,
	ScrollView,
	Text,
	TouchableOpacity,
	View,
} from "react-native";
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

	const openPlayer = async (sourceURL: string) => {
		const playerURL = dailymotionPlayerURL(sourceURL);
		if (!playerURL) {
			setError("Paste a Dailymotion video, dai.ly, or player URL");
			return;
		}

		try {
			const opened = await solNative.openDailymotionPlayer(playerURL);
			if (!opened) {
				throw new Error("The player window did not become visible");
			}
			setError("");
			void solNative.showToast("Floating player opened", "success");
		} catch {
			setError("Could not open the floating player");
			void solNative.showToast("Could not open floating player", "error");
		}
	};
	const openCurrent = () => void openPlayer(url);

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
				<TouchableOpacity
					className="px-3 py-2 rounded-lg subBg border border-color"
					onPress={() => store.ui.showSettings("DAILYMOTION")}
				>
					<Text className="text text-sm">Saved streams</Text>
				</TouchableOpacity>
			</View>

			<ScrollView
				className="flex-1"
				contentContainerClassName="px-10 py-6 gap-4 flex-grow"
				showsVerticalScrollIndicator
			>
				<View className="rounded-2xl border border-color subBg p-5 gap-2">
					<Text className="text-xs font-semibold darker-text">VIDEO URL</Text>
					<TextInput
						autoFocus
						enableFocusRing={false}
						className="text-base text"
						value={url}
						onChangeText={setURL}
						onSubmitEditing={openCurrent}
						placeholder="https://www.dailymotion.com/video/…"
					/>
				</View>

				{!!error && <Text className="text-sm text-red-500">{error}</Text>}

				{store.ui.dailymotionStreams.length > 0 && (
					<View className="rounded-xl border border-color subBg p-4 gap-2">
						<Text className="text-xs font-semibold darker-text">
							SAVED STREAMS
						</Text>
						<View className="flex-row flex-wrap gap-2">
							{store.ui.dailymotionStreams.map((stream) => (
								<TouchableOpacity
									key={stream.id}
									className="px-3 py-2 rounded-lg border border-color bg-neutral-100 dark:bg-neutral-700"
									onPress={() => void openPlayer(stream.url)}
								>
									<Text className="text-sm font-medium">▶ {stream.name}</Text>
								</TouchableOpacity>
							))}
						</View>
					</View>
				)}

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
					onPress={openCurrent}
				>
					<Text className="text-white font-semibold">Open floating player</Text>
				</TouchableOpacity>
			</ScrollView>
		</View>
	);
};
