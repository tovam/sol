import { BackButton } from "components/BackButton";
import { solNative } from "lib/SolNative";
import type { FC } from "react";
import {
	Clipboard,
	ScrollView,
	Text,
	TouchableOpacity,
	View,
} from "react-native";
import { useStore } from "store";
import { Widget } from "stores/ui.store";

const SECTIONS = [
	{
		title: "Sessions",
		commands: [
			["tmux", "Start a new session"],
			["tmux new -s name", "Start a named session"],
			["tmux ls", "List sessions"],
			["tmux attach -t name", "Attach to a session"],
			["tmux kill-session -t name", "Kill a session"],
		],
	},
	{
		title: "Windows",
		commands: [
			["Ctrl-b c", "Create window"],
			["Ctrl-b n / p", "Next / previous window"],
			["Ctrl-b 0…9", "Jump to window"],
			["Ctrl-b ,", "Rename window"],
			["Ctrl-b &", "Close window"],
		],
	},
	{
		title: "Panes",
		commands: [
			['Ctrl-b "', "Split vertically"],
			["Ctrl-b %", "Split horizontally"],
			["Ctrl-b arrows", "Move between panes"],
			["Ctrl-b z", "Zoom current pane"],
			["Ctrl-b x", "Close pane"],
			["Ctrl-b { / }", "Move pane left / right"],
		],
	},
	{
		title: "Copy & utility",
		commands: [
			["Ctrl-b [", "Enter copy mode"],
			["Ctrl-b ]", "Paste buffer"],
			["Ctrl-b d", "Detach"],
			["Ctrl-b ?", "Show all key bindings"],
			["Ctrl-b :", "Open command prompt"],
			["Ctrl-b t", "Show clock"],
		],
	},
] as const;

export const TmuxCheatsheetWidget: FC = () => {
	const store = useStore();
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
					<Text className="text-xl font-semibold text">tmux Cheatsheet</Text>
					<Text className="text-xs darker-text">
						Prefix: Ctrl-b · click any command to copy
					</Text>
				</View>
			</View>

			<ScrollView className="flex-1 px-5 py-4">
				<View className="flex-row flex-wrap gap-4 pb-5">
					{SECTIONS.map((section) => (
						<View
							key={section.title}
							className="w-[310px] rounded-xl border border-color subBg overflow-hidden"
						>
							<Text className="px-4 py-3 font-semibold text border-b border-color">
								{section.title}
							</Text>
							{section.commands.map(([command, description]) => (
								<TouchableOpacity
									key={command}
									className="px-4 py-2"
									onPress={() => {
										Clipboard.setString(command);
										void solNative.showToast("Command copied", "success");
									}}
								>
									<Text className="font-mono text-sm text">{command}</Text>
									<Text className="text-xs darker-text">{description}</Text>
								</TouchableOpacity>
							))}
						</View>
					))}
				</View>
			</ScrollView>
		</View>
	);
};
