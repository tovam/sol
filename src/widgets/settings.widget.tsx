import { KeyboardShortcutRecorderView } from "components/KeyboardShortcutRecorderView";
import { observer } from "mobx-react-lite";
import type { FC } from "react";
import { Text, View } from "react-native";
import { useStore } from "store";
import type { SettingsSection } from "stores/ui.store";
import { About } from "./settings/about";
import { AI } from "./settings/ai";
import { Calendars } from "./settings/calendars";
import { DailymotionSettings } from "./settings/dailymotion";
import { General } from "./settings/general";
import { Items } from "./settings/items";
import { Scripts } from "./settings/scripts";
import { Sidebar } from "./settings/sidebar";
import { Translate } from "./settings/translate";

const sectionDetails: Record<
	SettingsSection,
	{ title: string; description: string }
> = {
	GENERAL: {
		title: "General",
		description: "Window, search and system behavior",
	},
	AI: {
		title: "Artificial intelligence",
		description: "Providers, models, credentials and usage",
	},
	TRANSLATE: {
		title: "Translation",
		description: "Languages used by the translation command",
	},
	ITEMS: {
		title: "Items & shortcuts",
		description: "Visibility and global keyboard shortcuts",
	},
	SCRIPTS: {
		title: "Scripts",
		description: "Local commands discovered by Sol",
	},
	CALENDARS: {
		title: "Calendars",
		description: "Event display and calendar sources",
	},
	DAILYMOTION: {
		title: "Dailymotion",
		description: "Saved streams and direct commands",
	},
	ABOUT: {
		title: "About Sol",
		description: "Version and project links",
	},
};

export const SettingsWidget: FC = observer(() => {
	const store = useStore();
	const showKeyboardRecorder = store.ui.showKeyboardRecorder;
	const selected = store.ui.settingsSection;
	const section = sectionDetails[selected];
	return (
		<View className="flex-1 flex-row">
			<Sidebar setSelected={store.ui.setSettingsSection} selected={selected} />
			<View className="flex-1 h-full bg-neutral-100 dark:bg-neutral-800">
				<View className="h-10 px-3 flex-row items-center gap-2 border-b border-color">
					<Text className="text-sm font-semibold text">{section.title}</Text>
					<Text className="flex-1 text-xs darker-text" numberOfLines={1}>
						{section.description}
					</Text>
				</View>
				<View className="flex-1">
					{selected === "GENERAL" && <General />}
					{selected === "ITEMS" && <Items />}
					{selected === "TRANSLATE" && <Translate />}
					{selected === "SCRIPTS" && <Scripts />}
					{selected === "CALENDARS" && <Calendars />}
					{selected === "AI" && <AI />}
					{selected === "DAILYMOTION" && <DailymotionSettings />}
					{selected === "ABOUT" && <About />}
				</View>
			</View>
			{showKeyboardRecorder && (
				<View className="absolute top-0 bottom-0 left-0 right-0 bg-black/80 items-center justify-center">
					<KeyboardShortcutRecorderView
						className={"w-80 h-24"}
						onShortcutChange={(e) => {
							store.ui.setShortcutFromUI(e.nativeEvent.shortcut);
						}}
						onCancel={() => {
							store.ui.closeKeyboardRecorder();
						}}
					/>
				</View>
			)}
		</View>
	);
});
