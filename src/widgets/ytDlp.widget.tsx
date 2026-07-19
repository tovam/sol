import { BackButton } from "components/BackButton";
import { solNative } from "lib/SolNative";
import { type FC, useCallback, useEffect, useState } from "react";
import { Clipboard, Text, TouchableOpacity, View } from "react-native";
import { TextInput } from "react-native-macos";
import { useStore } from "store";
import { Widget } from "stores/ui.store";

type DownloadMode = "video" | "audio";

function shellQuote(value: string) {
	return ["'", value.split("'").join("'\"'\"'"), "'"].join("");
}

function isSupportedURL(value: string) {
	return /^https?:\/\/\S+$/i.test(value.trim());
}

export const YtDlpWidget: FC = () => {
	const store = useStore();
	const [url, setURL] = useState("");
	const [mode, setMode] = useState<DownloadMode>("video");
	const [isAvailable, setIsAvailable] = useState<boolean | null>(null);
	const [error, setError] = useState("");

	const checkAvailability = useCallback(async () => {
		try {
			const executable =
				await solNative.executeBashScriptWithOutput("command -v yt-dlp");
			setIsAvailable(Boolean(executable.trim()));
		} catch {
			setIsAvailable(false);
		}
	}, []);

	useEffect(() => {
		void checkAvailability();
		Clipboard.getString().then((clipboardText) => {
			if (isSupportedURL(clipboardText)) setURL(clipboardText.trim());
		});
	}, [checkAvailability]);

	const download = () => {
		if (!isSupportedURL(url)) {
			setError("Enter a valid http or https URL");
			return;
		}
		setError("");
		const modeArguments =
			mode === "audio"
				? "--extract-audio --audio-format mp3"
				: "--format 'bv*+ba/b'";
		const command = [
			"yt-dlp",
			"--no-playlist",
			"--newline",
			modeArguments,
			'-P "$HOME/Downloads"',
			shellQuote(url.trim()),
		].join(" ");
		void solNative.executeBashScript(command);
		void solNative.showToast("Download started", "success");
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
					<Text className="text-xl font-semibold text">yt-dlp Downloader</Text>
					<Text className="text-xs darker-text">
						Downloads into your Downloads folder
					</Text>
				</View>
			</View>

			<View className="flex-1 px-10 py-8 gap-5">
				<View className="rounded-xl border border-color subBg p-4">
					<Text className="text-xs font-semibold darker-text mb-2">URL</Text>
					<TextInput
						autoFocus
						enableFocusRing={false}
						className="text-base text"
						value={url}
						onChangeText={setURL}
						onSubmitEditing={download}
						placeholder="https://…"
					/>
				</View>

				<View className="flex-row gap-3">
					{(["video", "audio"] as const).map((nextMode) => (
						<TouchableOpacity
							key={nextMode}
							className={`flex-1 py-4 rounded-xl border items-center ${
								mode === nextMode
									? "bg-accent-strong border-transparent"
									: "subBg border-color"
							}`}
							onPress={() => setMode(nextMode)}
						>
							<Text
								className={
									mode === nextMode ? "text-white font-semibold" : "text"
								}
							>
								{nextMode === "video" ? "Best video" : "MP3 audio"}
							</Text>
						</TouchableOpacity>
					))}
				</View>

				{!!error && <Text className="text-sm text-red-500">{error}</Text>}
				{isAvailable === false && (
					<View className="rounded-xl border border-orange-500/40 bg-orange-500/10 p-4 gap-2">
						<Text className="text font-semibold">yt-dlp is not installed</Text>
						<Text className="text-sm darker-text">
							Install it first with Homebrew, then check again.
						</Text>
						<View className="flex-row gap-2">
							<TouchableOpacity
								className="px-4 py-2 rounded-lg subBg border border-color"
								onPress={() => {
									void solNative.executeBashScript("brew install yt-dlp");
								}}
							>
								<Text className="text">Install with Homebrew</Text>
							</TouchableOpacity>
							<TouchableOpacity
								className="px-4 py-2 rounded-lg subBg border border-color"
								onPress={() => void checkAvailability()}
							>
								<Text className="text">Check again</Text>
							</TouchableOpacity>
						</View>
					</View>
				)}

				<TouchableOpacity
					className={`mt-auto py-4 rounded-xl items-center ${
						isAvailable ? "bg-accent-strong" : "bg-neutral-500"
					}`}
					disabled={!isAvailable}
					onPress={download}
				>
					<Text className="text-white font-semibold">
						{isAvailable === null ? "Checking yt-dlp…" : "Download"}
					</Text>
				</TouchableOpacity>
			</View>
		</View>
	);
};
