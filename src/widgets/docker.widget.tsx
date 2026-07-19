import { BackButton } from "components/BackButton";
import { solNative } from "lib/SolNative";
import { type FC, useCallback, useEffect, useState } from "react";
import {
	ActivityIndicator,
	Clipboard,
	ScrollView,
	Text,
	TouchableOpacity,
	View,
} from "react-native";
import { useStore } from "store";
import { Widget } from "stores/ui.store";

type DockerContainer = {
	ID: string;
	Image: string;
	Names: string;
	Ports: string;
	State: string;
	Status: string;
};

export const DockerWidget: FC = () => {
	const store = useStore();
	const [containers, setContainers] = useState<DockerContainer[]>([]);
	const [loading, setLoading] = useState(true);
	const [error, setError] = useState("");

	const refresh = useCallback(async () => {
		setLoading(true);
		try {
			const output = await solNative.executeBashScriptWithOutput(
				"docker ps --no-trunc --format '{{json .}}'",
			);
			const nextContainers = output
				.split("\n")
				.map((line) => line.trim())
				.filter((line) => line.startsWith("{"))
				.map((line) => JSON.parse(line) as DockerContainer);
			setContainers(nextContainers);
			setError("");
		} catch (nextError) {
			setContainers([]);
			setError(
				String(nextError)
					.replace(/^Error:\s*/, "")
					.trim(),
			);
		} finally {
			setLoading(false);
		}
	}, []);

	useEffect(() => {
		void refresh();
		const interval = setInterval(() => void refresh(), 5_000);
		return () => clearInterval(interval);
	}, [refresh]);

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
					<Text className="text-xl font-semibold text">Docker PS</Text>
					<Text className="text-xs darker-text">
						Running containers · refreshes every 5 seconds
					</Text>
				</View>
				<TouchableOpacity
					className="px-4 py-2 rounded-lg subBg border border-color"
					onPress={() => void refresh()}
				>
					<Text className="text">Refresh</Text>
				</TouchableOpacity>
			</View>

			<View className="h-9 px-5 flex-row items-center border-b border-color subBg">
				<Text className="w-32 text-xs font-semibold darker-text">NAME</Text>
				<Text className="w-44 text-xs font-semibold darker-text">IMAGE</Text>
				<Text className="flex-1 text-xs font-semibold darker-text">STATUS</Text>
				<Text className="w-40 text-xs font-semibold darker-text">PORTS</Text>
			</View>

			{loading && containers.length === 0 ? (
				<View className="flex-1 items-center justify-center gap-3">
					<ActivityIndicator />
					<Text className="darker-text">Running docker ps…</Text>
				</View>
			) : error ? (
				<View className="flex-1 items-center justify-center px-12 gap-2">
					<Text className="text-lg font-semibold text">Docker unavailable</Text>
					<Text className="text-sm darker-text text-center">{error}</Text>
				</View>
			) : containers.length === 0 ? (
				<View className="flex-1 items-center justify-center">
					<Text className="darker-text">No running containers</Text>
				</View>
			) : (
				<ScrollView className="flex-1 px-3 py-2">
					{containers.map((container) => (
						<TouchableOpacity
							key={container.ID}
							className="h-14 px-2 flex-row items-center rounded-xl"
							onPress={() => {
								Clipboard.setString(container.ID);
								void solNative.showToast("Container ID copied", "success");
							}}
						>
							<Text
								className="w-32 text-sm font-semibold text"
								numberOfLines={1}
							>
								{container.Names}
							</Text>
							<Text className="w-44 text-sm darker-text" numberOfLines={1}>
								{container.Image}
							</Text>
							<Text className="flex-1 text-sm text" numberOfLines={1}>
								{container.Status}
							</Text>
							<Text className="w-40 text-xs darker-text" numberOfLines={1}>
								{container.Ports || "—"}
							</Text>
						</TouchableOpacity>
					))}
				</ScrollView>
			)}
		</View>
	);
};
