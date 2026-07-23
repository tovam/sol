import { Assets } from "assets";
import { solNative } from "lib/SolNative";
import { observer } from "mobx-react-lite";
import type { FC } from "react";
import { Image, ScrollView, Text, View } from "react-native";
import { useStore } from "store";

export const Scripts: FC = observer(() => {
	const store = useStore();
	const username = solNative.userName();

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
						<Text className="font-bold">
							/Users/{username}/.config/sol/scripts
						</Text>
						.
					</Text>
					<Text className="text-xxs text-neutral-500 dark:text-neutral-400 mt-1">
						Place your scripts in this folder to have them automatically picked
						up by Sol.
					</Text>
					<Text className="text-xxs text-neutral-500 dark:text-neutral-400 mt-1">
						Each script supports these metadata comments:
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
				</View>
			</View>
			<View className="p-2.5 subBg gap-2 rounded-lg border border-lightBorder dark:border-darkBorder">
				<Text className="text-sm font-semibold mb-1">Detected Scripts</Text>
				{store.scripts.scripts.length === 0 ? (
					<Text className="italic text-neutral-500">No scripts found.</Text>
				) : (
					store.scripts.scripts.map((script) => (
						<View key={script.id} className="mb-1 flex-row items-center">
							<Text className="mr-2">{script.icon}</Text>
							<Text className="text-xs mr-2">{script.name}</Text>
							<View className="flex-1" />
							<Text className="text-xs text-neutral-500">
								{script.command ? `${script.command} · ` : ""}
								{script.id.replace("script-", "")}
							</Text>
						</View>
					))
				)}
			</View>
		</ScrollView>
	);
});
