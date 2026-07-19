import { BackButton } from "components/BackButton";
import { solNative } from "lib/SolNative";
import { type FC, useCallback, useEffect, useState } from "react";
import {
	ActivityIndicator,
	Clipboard,
	Image,
	Text,
	TouchableOpacity,
	View,
} from "react-native";
import { TextInput } from "react-native-macos";
import { useStore } from "store";
import { Widget } from "stores/ui.store";

export const QRCodeWidget: FC = () => {
	const store = useStore();
	const [text, setText] = useState("");
	const [qrData, setQrData] = useState("");
	const [loading, setLoading] = useState(false);
	const [error, setError] = useState("");

	const generate = useCallback(async (value: string) => {
		const normalized = value.trim();
		if (!normalized) {
			setQrData("");
			setError("Enter some text first");
			return;
		}
		setLoading(true);
		try {
			setQrData(await solNative.generateQRCode(normalized));
			setError("");
		} catch (nextError) {
			setError(String(nextError));
		} finally {
			setLoading(false);
		}
	}, []);

	useEffect(() => {
		Clipboard.getString().then((clipboardText) => {
			if (!clipboardText) return;
			setText(clipboardText);
		});
	}, []);

	useEffect(() => {
		if (!text.trim()) {
			setQrData("");
			setError("");
			return;
		}

		const debounce = setTimeout(() => {
			void generate(text);
		}, 180);
		return () => clearTimeout(debounce);
	}, [generate, text]);

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
					<Text className="text-xl font-semibold text">QR Code Generator</Text>
					<Text className="text-xs darker-text">
						Starts with the clipboard and updates as you type
					</Text>
				</View>
			</View>

			<View className="flex-1 flex-row gap-8 p-7">
				<View className="flex-1 gap-3">
					<View className="flex-1 rounded-xl border border-color subBg p-3">
						<TextInput
							autoFocus
							enableFocusRing={false}
							multiline
							className="flex-1 text-base text"
							value={text}
							onChangeText={setText}
							placeholder="Text, URL, Wi-Fi info…"
						/>
					</View>
					<View className="flex-row gap-2">
						<TouchableOpacity
							className="flex-1 py-3 rounded-xl bg-accent-strong items-center"
							onPress={() => void generate(text)}
						>
							<Text className="text-white font-semibold">Generate</Text>
						</TouchableOpacity>
						<TouchableOpacity
							className="px-5 py-3 rounded-xl subBg border border-color"
							onPress={() => {
								Clipboard.setString(text);
								void solNative.showToast("Text copied", "success");
							}}
						>
							<Text className="text font-semibold">Copy text</Text>
						</TouchableOpacity>
					</View>
				</View>

				<View className="w-64 items-center justify-center rounded-2xl bg-white border border-color">
					{loading ? (
						<ActivityIndicator />
					) : qrData ? (
						<Image
							source={{ uri: qrData }}
							style={{ width: 224, height: 224 }}
						/>
					) : (
						<Text className="text-neutral-500 text-center px-6">
							{error || "Your QR code appears here"}
						</Text>
					)}
				</View>
			</View>
		</View>
	);
};
