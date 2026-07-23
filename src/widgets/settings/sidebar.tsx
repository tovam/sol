import { Assets, Icons } from "assets";
import { BackButton } from "components/BackButton";
import clsx from "clsx";
import { useBoolean } from "hooks";
import type { ImageSourcePropType } from "react-native";
import {
	Image,
	Text,
	TouchableWithoutFeedback,
	useColorScheme,
	View,
} from "react-native";
import { useStore } from "store";
import { type SettingsSection, Widget } from "stores/ui.store";

type NavigationItem = {
	section: SettingsSection;
	title: string;
	icon: ImageSourcePropType;
	preserveIconColor?: boolean;
};

const PRIMARY_ITEMS: NavigationItem[] = [
	{ section: "GENERAL", title: "General", icon: Icons.Gears },
	{ section: "AI", title: "AI", icon: Icons.Robot },
	{ section: "TRANSLATE", title: "Translation", icon: Icons.World },
	{ section: "CALENDARS", title: "Calendars", icon: Icons.Calendar },
	{ section: "DAILYMOTION", title: "Dailymotion", icon: Icons.Video },
];

const MANAGE_ITEMS: NavigationItem[] = [
	{ section: "ITEMS", title: "Items & shortcuts", icon: Icons.Dashboard },
	{ section: "SCRIPTS", title: "Scripts", icon: Icons.Terminal },
];

const ABOUT_ITEM: NavigationItem = {
	section: "ABOUT",
	title: "About Sol",
	icon: Assets.smallLogo,
	preserveIconColor: true,
};

const SidebarItem = ({
	item,
	selected,
	onPress,
}: {
	item: NavigationItem;
	selected: boolean;
	onPress: () => void;
}) => {
	const [hovered, hoverOn, hoverOff] = useBoolean();
	const colorScheme = useColorScheme();
	const iconTint = selected
		? "white"
		: colorScheme === "dark"
			? "#d4d4d8"
			: "#3f3f46";

	return (
		<TouchableWithoutFeedback
			onPress={onPress}
			onMouseEnter={hoverOn}
			onMouseLeave={hoverOff}
			// @ts-expect-error macOS-only focus ring option
			enableFocusRing={false}
		>
			<View
				className={clsx(
					"h-9 px-2 rounded-lg flex-row items-center gap-2",
					{
						"bg-accent-strong": selected,
						"bg-neutral-200 dark:bg-neutral-800": hovered && !selected,
					},
				)}
			>
				<View
					className={clsx(
						"h-6 w-6 rounded-md items-center justify-center",
						{
							"bg-white/10": selected,
							"bg-black/5 dark:bg-white/5": !selected,
						},
					)}
				>
					<Image
						source={item.icon}
						className="h-4 w-4"
						resizeMode="contain"
						style={
							item.preserveIconColor ? undefined : { tintColor: iconTint }
						}
					/>
				</View>
				<Text
					numberOfLines={1}
					className={clsx("flex-1 text-sm", {
						"text-white font-semibold": selected,
						"text": !selected,
					})}
				>
					{item.title}
				</Text>
			</View>
		</TouchableWithoutFeedback>
	);
};

const SidebarGroup = ({
	label,
	items,
	selected,
	setSelected,
}: {
	label: string;
	items: NavigationItem[];
	selected: SettingsSection;
	setSelected: (selected: SettingsSection) => unknown;
}) => (
	<View className="gap-0.5">
		<Text className="px-2 mb-1 text-[10px] font-semibold uppercase tracking-wide darker-text">
			{label}
		</Text>
		{items.map((item) => (
			<SidebarItem
				key={item.section}
				item={item}
				selected={selected === item.section}
				onPress={() => setSelected(item.section)}
			/>
		))}
	</View>
);

export const Sidebar = ({
	selected,
	setSelected,
}: {
	selected: SettingsSection;
	setSelected: (selected: SettingsSection) => unknown;
}) => {
	const store = useStore();

	return (
		<View className="w-48 px-2.5 py-2.5 bg-neutral-100 dark:bg-neutral-900 border-r border-color">
			<View className="h-10 px-1 flex-row items-center gap-2 mb-3">
				<BackButton onPress={() => store.ui.focusWidget(Widget.SEARCH)} />
				<Image
					source={Assets.smallLogo}
					className="h-6 w-6 rounded-full"
					resizeMode="contain"
				/>
				<View>
					<Text className="text-sm font-semibold text">Settings</Text>
					<Text className="text-[10px] darker-text">Sol</Text>
				</View>
			</View>

			<View className="gap-4">
				<SidebarGroup
					label="Preferences"
					items={PRIMARY_ITEMS}
					selected={selected}
					setSelected={setSelected}
				/>
				<SidebarGroup
					label="Manage"
					items={MANAGE_ITEMS}
					selected={selected}
					setSelected={setSelected}
				/>
			</View>

			<View className="flex-1" />
			<View className="pt-2 border-t border-color">
				<SidebarItem
					item={ABOUT_ITEM}
					selected={selected === "ABOUT"}
					onPress={() => setSelected("ABOUT")}
				/>
			</View>
		</View>
	);
};
