import { Assets } from "assets";
import { solNative } from "lib/SolNative";
import { observer } from "mobx-react-lite";
import type { FC } from "react";
import {
	Image,
	ScrollView,
	Text,
	TouchableOpacity,
	View,
} from "react-native";
import { useStore } from "store";

export const Scripts: FC = observer(() => {
	const store = useStore();
	const username = solNative.userName();
	const defaultScriptsDirectory = `/Users/${username}/.config/sol/scripts`;

	const addScriptDirectory = async () => {
		try {
			solNative.hideWindow();
			const selectedDirectory = await solNative.openFilePicker();
			if (
				selectedDirectory &&
				!store.ui.addScriptDirectory(selectedDirectory)
			) {
				void solNative.showToast(
					"This scripts folder is already configured.",
					"error",
				);
			}
		} catch {
			// The native picker rejects when the user cancels.
		} finally {
			solNative.showWindow();
		}
	};

	return (
		<ScrollView
			showsVerticalScrollIndicator={false}
			automaticallyAdjustContentInsets
			className="flex-1"
			contentContainerClassName="p-3 gap-1.5"
		>
			<View className="flex-row items-start p-2.5 subBg rounded-lg border border-lightBorder dark:border-darkBorder">
				<Image
					source={Assets.terminal}
					className="h-6 w-6 mr-2"
					resizeMode="contain"
				/>
				<View className="flex-1">
					<Text className="text-xxs text-neutral-500 dark:text-neutral-400">
						Scripts are located at{" "}
						<Text className="font-bold">{defaultScriptsDirectory}</Text>
						.
					</Text>
					<Text className="text-xxs text-neutral-500 dark:text-neutral-400 mt-1">
						Place your scripts in this folder to have them automatically picked
						up by Sol.
					</Text>
					<Text className="text-xxs text-neutral-500 dark:text-neutral-400 mt-1">
						Sol metadata:
					</Text>
					<Text className="text-xxs text-neutral-500 dark:text-neutral-400 mt-1">
						# name: Script Name
					</Text>
					<Text className="text-xxs text-neutral-500 dark:text-neutral-400 mt-1">
						# icon: Emoji Icon
					</Text>
					<Text className="text-xxs text-neutral-500 dark:text-neutral-400 mt-1">
						# command: my-command (optional, shell scripts only)
					</Text>
					<Text className="text-xxs text-neutral-500 dark:text-neutral-400 mt-1">
						# arguments: raw | shlex (optional; raw by default)
					</Text>
					<Text className="text-xxs text-neutral-500 dark:text-neutral-400 mt-1">
						Raw passes the complete suffix safely as $1. Shlex understands
						quotes and passes separate values as $1, $2, etc. A command with no
						text receives no argument.
					</Text>
					<Text className="text-xxs text-neutral-500 dark:text-neutral-400 mt-1">
						Command names use letters, numbers, dots, dashes or underscores; ai,
						ia and dm are reserved.
					</Text>
					<Text className="text-xxs text-neutral-500 dark:text-neutral-400 mt-2">
						Raycast Script Commands are also supported: @raycast.schemaVersion,
						title, mode, icon, packageName, description, author and authorURL.
						Relative icon paths are resolved from the script folder. Silent mode
						runs without an output panel; other modes use Sol&apos;s compact
						output panel.
					</Text>
				</View>
			</View>
			<View className="p-2.5 subBg gap-2 rounded-lg border border-lightBorder dark:border-darkBorder">
				<View className="flex-row items-center gap-3">
					<View className="flex-1">
						<Text className="text-sm font-semibold text">Script folders</Text>
						<Text className="text-xxs darker-text">
							The default folder is always enabled. Add any other folders you
							want Sol to watch.
						</Text>
					</View>
					<TouchableOpacity
						className="px-2.5 py-1.5 rounded-md bg-accent-strong"
						onPress={() => void addScriptDirectory()}
					>
						<Text className="text-xs font-semibold text-white">Add folder</Text>
					</TouchableOpacity>
				</View>

				<View className="border-t border-color" />
				<View className="flex-row items-center gap-2 py-1">
					<View className="w-2 h-2 rounded-full bg-green-500" />
					<Text className="flex-1 text-xs" numberOfLines={1}>
						{defaultScriptsDirectory}
					</Text>
					<Text className="text-xxs darker-text">Default</Text>
				</View>

				{store.ui.scriptDirectories.map((directory) => (
					<View
						key={directory}
						className="flex-row items-center gap-2 py-1 border-t border-color"
					>
						<View className="w-2 h-2 rounded-full bg-green-500" />
						<Text className="flex-1 text-xs" numberOfLines={1}>
							{directory}
						</Text>
						<TouchableOpacity
							className="px-2 py-1"
							onPress={() => store.ui.removeScriptDirectory(directory)}
						>
							<Text className="text-xs text-red-500">Remove</Text>
						</TouchableOpacity>
					</View>
				))}
			</View>
			<View className="p-2.5 subBg gap-2 rounded-lg border border-lightBorder dark:border-darkBorder">
				<Text className="text-sm font-semibold mb-1">Detected Scripts</Text>
				{store.scripts.scripts.length === 0 ? (
					<Text className="italic text-neutral-500">No scripts found.</Text>
				) : (
					store.scripts.scripts.map((script) => (
						<View key={script.id} className="mb-1 flex-row items-center">
							{script.iconImage ? (
								<Image
									source={script.iconImage}
									className="w-5 h-5 mr-2"
									resizeMode="contain"
								/>
							) : (
								<Text className="mr-2">{script.icon}</Text>
							)}
							<Text className="text-xs mr-2">{script.name}</Text>
							<View className="flex-1" />
							<Text
								className="max-w-[55%] text-xs text-neutral-500"
								numberOfLines={1}
							>
								{script.command ? `${script.command} · ` : ""}
								{script.scriptPath ?? script.id.replace("script-", "")}
							</Text>
						</View>
					))
				)}
			</View>
		</ScrollView>
	);
});
