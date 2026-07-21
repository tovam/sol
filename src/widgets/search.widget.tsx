import { LegendList, type LegendListRef } from "@legendapp/list/react-native";
import { Icons } from "assets";
import clsx from "clsx";
import Favicon from "components/Favicon";
import { FileIcon } from "components/FileIcon";
import { FileSortControl } from "components/FileSortControl";
import { Key } from "components/Key";
import { LoadingBar } from "components/LoadingBar";
import { MainInput } from "components/MainInput";
import { isNetworkQuery, NetworkPanel } from "components/NetworkPanel";
import { renderToKeys } from "lib/shortcuts";
import { observer } from "mobx-react-lite";
import { type FC, useEffect, useRef, useState } from "react";
import {
	Image,
	Platform,
	StyleSheet,
	Text,
	TouchableOpacity,
	View,
} from "react-native";
import { useStore } from "store";
import { ItemType, SearchTab, Widget } from "stores/ui.store";
import type { TemporaryResult } from "stores/ui.store.helpers";

const SEARCH_TABS = [
	{ value: SearchTab.ALL, label: "All", placeholder: "Search" },
	{
		value: SearchTab.APPLICATIONS,
		label: "Applications",
		placeholder: "Search applications",
	},
	{ value: SearchTab.FILES, label: "Files", placeholder: "Search files" },
	{ value: SearchTab.ACTIONS, label: "Actions", placeholder: "Search actions" },
];

function TemporaryResultView({
	result,
	isActive,
}: {
	result: TemporaryResult;
	isActive: boolean;
}) {
	if (result.kind === "comparison") {
		if (result.layout === "inline") {
			return (
				<View className="flex-1 px-4 flex-row items-center justify-between gap-4">
					<Text className="flex-1 text-2xl font-semibold" numberOfLines={1}>
						{result.left.value}
					</Text>
					<Text className="text-lg darker-text">→</Text>
					<Text
						className="flex-1 text-2xl font-semibold text-right"
						numberOfLines={1}
					>
						{result.right.value}
					</Text>
				</View>
			);
		}

		return (
			<View className="flex-1 px-4">
				<View className="flex-row items-center justify-between gap-4">
					<View className="flex-1">
						<Text
							className={clsx("text-xs uppercase darker-text", {
								"text-white dark:text-neutral-100": isActive,
							})}
						>
							{result.left.label}
						</Text>
						<Text className="text-2xl font-semibold">{result.left.value}</Text>
					</View>
					<Text className="text-lg darker-text">→</Text>
					<View className="flex-1 items-end">
						<Text
							className={clsx("text-xs uppercase darker-text", {
								"text-white dark:text-neutral-100": isActive,
							})}
						>
							{result.right.label}
						</Text>
						<Text className="text-2xl font-semibold">{result.right.value}</Text>
					</View>
				</View>
				{!!result.footer && (
					<Text className="mt-2 text-xs darker-text">{result.footer}</Text>
				)}
			</View>
		);
	}

	if (result.kind === "flight") {
		return (
			<View className="flex-1 px-4">
				<Text className="text-xl font-semibold">{result.flight}</Text>
				<View className="mt-1 flex-row flex-wrap gap-x-3 gap-y-1">
					{!!result.status && (
						<Text className="text-sm darker-text">Status: {result.status}</Text>
					)}
					{!!result.departureTime && (
						<Text className="text-sm darker-text">
							Departure: {result.departureTime}
						</Text>
					)}
					{!!result.arrivalTime && (
						<Text className="text-sm darker-text">
							Arrival: {result.arrivalTime}
						</Text>
					)}
					{!!result.terminal && (
						<Text className="text-sm darker-text">
							Terminal: {result.terminal}
						</Text>
					)}
					{!!result.gate && (
						<Text className="text-sm darker-text">Gate: {result.gate}</Text>
					)}
				</View>
			</View>
		);
	}

	return (
		<View className={clsx("flex-1 px-4 flex-row items-center")}>
			<Text className="text-4xl font-semibold flex-1">{result.value}</Text>
			{!!result.secondary && (
				<Text className="text-neutral-600 dark:text-neutral-400">
					{result.secondary}
				</Text>
			)}
		</View>
	);
}

function compactPath(path: string, username: string) {
	const home = `/Users/${username}`;
	if (path === home) return "~";
	if (path.startsWith(`${home}/`)) return `~${path.slice(home.length)}`;
	return path;
}

function parentDirectory(path: string, username: string) {
	const normalized = path.replace(/\/+$/, "");
	const separatorIndex = normalized.lastIndexOf("/");
	if (separatorIndex <= 0) return "/";
	return compactPath(normalized.slice(0, separatorIndex), username);
}

function getItemMetadata(item: Item, username: string) {
	const details: string[] = [];

	switch (item.type) {
		case ItemType.APPLICATION:
			details.push("Application");
			if (item.url) details.push(parentDirectory(item.url, username));
			break;
		case ItemType.FILE:
			details.push("File");
			if (item.url) details.push(parentDirectory(item.url, username));
			break;
		case ItemType.CONFIGURATION:
			details.push("Action");
			break;
		case ItemType.PREFERENCE_PANE:
			details.push("System setting");
			break;
		case ItemType.CUSTOM:
			details.push("Quick link");
			break;
		case ItemType.USER_SCRIPT:
			details.push("Script");
			break;
		case ItemType.BOOKMARK:
			details.push("Browser bookmark");
			if (item.bookmarkFolder) details.push(item.bookmarkFolder);
			break;
		case ItemType.TEMPORARY_RESULT:
			details.push("Result");
			break;
	}

	if (item.subName) details.push(item.subName);
	return details.join(" · ");
}

function ItemIcon({
	item,
	isActive,
	isDarkMode,
}: {
	item: Item;
	isActive: boolean;
	isDarkMode: boolean;
}) {
	let icon = null;
	const adaptiveTint =
		item.id === "process_manager"
			? isActive
				? "#ffffff"
				: isDarkMode
					? "#ffffffb8"
					: "#000000b8"
			: undefined;

	if (item.type === ItemType.BOOKMARK && item.url) {
		icon = (
			<Favicon
				url={item.url}
				fallback={item.faviconFallback}
				className="w-6 h-6"
			/>
		);
	} else if (
		(item.type === ItemType.APPLICATION || item.type === ItemType.FILE) &&
		item.url
	) {
		icon = <FileIcon url={item.url} className="w-6 h-6" />;
	} else if (item.type === ItemType.CUSTOM && item.icon) {
		icon = (
			<View className="w-6 h-6 rounded items-center justify-center bg-white dark:bg-black">
				<Image
					// @ts-expect-error custom icon names are validated when the item is created
					source={Icons[item.icon]}
					style={{ tintColor: item.color, height: 16, width: 16 }}
				/>
			</View>
		);
	} else if (item.iconImage) {
		icon = (
			<Image
				source={item.iconImage}
				className="w-6 h-6"
				resizeMode="contain"
				style={adaptiveTint ? { tintColor: adaptiveTint } : undefined}
			/>
		);
	} else if (
		(Platform.OS === "macos" || Platform.OS === "ios") &&
		item.IconComponent
	) {
		icon = <item.IconComponent />;
	} else if (item.icon) {
		icon = (
			<Text style={{ fontSize: 19, lineHeight: 24, textAlign: "center" }}>
				{item.icon}
			</Text>
		);
	}

	return (
		<View className="relative w-8 h-8 shrink-0 items-center justify-center">
			{icon}
			{item.type === ItemType.APPLICATION && item.isRunning && (
				<View
					accessible
					accessibilityLabel={`${item.name} is running`}
					className="absolute top-0.5 right-0.5 w-2 h-2 rounded-full bg-[#5f936d] dark:bg-[#75a681] border border-black/20 dark:border-white/20"
				/>
			)}
		</View>
	);
}

const ItemRow = observer(({ item, index }: { item: Item; index: number }) => {
	const store = useStore();
	const isActive = index === store.ui.selectedIndex;
	const metadata = getItemMetadata(item, store.ui.username);

	// this is used for things like calculator results
	if (item.type === ItemType.TEMPORARY_RESULT) {
		if (store.ui.temporaryResult == null) {
			return null;
		}

		return (
			<View
				className={clsx("flex-row items-center rounded-xl py-5", {
					highlight: isActive,
				})}
			>
				<TemporaryResultView
					result={store.ui.temporaryResult}
					isActive={isActive}
				/>
			</View>
		);
	}

	return (
		<TouchableOpacity
			onPress={() => {
				store.ui.setSelectedIndex(index);
				store.keystroke.simulateEnter();
			}}
		>
			<View
				className={clsx("flex-1 flex-row items-center px-4 h-14 rounded-xl", {
					"bg-accent-strong": isActive,
				})}
			>
				<ItemIcon
					item={item}
					isActive={isActive}
					isDarkMode={store.ui.isDarkMode}
				/>
				<Text
					numberOfLines={1}
					className={clsx("ml-3 text flex-1", {
						"text-white": isActive,
					})}
				>
					{item.name}
				</Text>

				{!!metadata && (
					<Text
						numberOfLines={1}
						className={clsx("darker-text text-xs", {
							"text-white dark:text-neutral-200": isActive,
						})}
						style={{ maxWidth: 300, marginLeft: 16, textAlign: "right" }}
					>
						{metadata}
					</Text>
				)}

				{!!store.ui.shortcuts[item.id] && (
					<View className="ml-3 flex-row gap-1 items-center shrink-0">
						{renderToKeys(store.ui.shortcuts[item.id])}
					</View>
				)}
			</View>
		</TouchableOpacity>
	);
});

const EmptyComponent = ({ message = "No Results" }: { message?: string }) => {
	return (
		<View className="flex-1 items-center justify-center">
			<Text className="text-neutral-400 dark:text-neutral-500 text-base">
				{message}
			</Text>
		</View>
	);
};

export const SearchWidget: FC = observer(() => {
	const store = useStore();
	const focused = store.ui.focusedWidget === Widget.SEARCH;
	const selectedIndex = store.ui.selectedIndex;
	const listRef = useRef<LegendListRef | null>(null);
	const items = store.ui.searchItems;
	const activeTab = store.ui.searchTab;
	const activeTabConfig =
		SEARCH_TABS.find((tab) => tab.value === activeTab) ?? SEARCH_TABS[0];
	const showResults = !!store.ui.query || activeTab !== SearchTab.ALL;
	const showNetworkPanel =
		(activeTab === SearchTab.ALL || activeTab === SearchTab.ACTIONS) &&
		isNetworkQuery(store.ui.query);
	const temporaryActionLabel =
		store.ui.temporaryResult?.kind === "text"
			? store.ui.temporaryResult.actionLabel
			: undefined;
	const [listViewportHeight, setListViewportHeight] = useState(0);
	const [listContentHeight, setListContentHeight] = useState(0);
	const [listOffset, setListOffset] = useState(0);
	const scrollTrackHeight = Math.max(0, listViewportHeight - 24);
	const scrollThumbHeight = Math.max(
		28,
		(listViewportHeight / Math.max(listContentHeight, 1)) * scrollTrackHeight,
	);
	const maxScrollOffset = Math.max(1, listContentHeight - listViewportHeight);
	const scrollThumbOffset =
		(Math.min(Math.max(listOffset, 0), maxScrollOffset) / maxScrollOffset) *
		Math.max(0, scrollTrackHeight - scrollThumbHeight);
	const hasOverflow = listContentHeight > listViewportHeight + 1;

	useEffect(() => {
		if (focused && items.length && selectedIndex < items.length) {
			listRef.current?.scrollToIndex({
				index: selectedIndex,
				viewOffset: 80,
			});
		}
	}, [focused, selectedIndex, items]);

	useEffect(() => {
		if (activeTab !== SearchTab.FILES) return;
		const timer = setTimeout(() => {
			void store.ui.runFileSearch(store.ui.query);
		}, 150);
		return () => clearTimeout(timer);
	}, [
		activeTab,
		store.ui.query,
		store.ui.fileSort,
		store.ui.runFileSearch,
	]);

	return (
		<View
			className={clsx({
				"flex-1": showResults,
			})}
		>
			<View className="flex-row items-center">
				<MainInput
					className="flex-1"
					placeholder={activeTabConfig.placeholder}
				/>
			</View>

			{!!store.ui.query && (
				<View className="h-9 px-3 flex-row items-center border-b border-color">
					{SEARCH_TABS.map((tab) => {
						const isActive = tab.value === activeTab;
						return (
							<TouchableOpacity
								key={tab.value}
								onPress={() => store.ui.setSearchTab(tab.value)}
							>
								<View className="h-full px-3 items-center justify-center relative">
									<Text
										className={clsx("text-xs darker-text", {
											"text font-semibold": isActive,
										})}
									>
										{tab.label}
									</Text>
									{isActive && (
										<View className="absolute bottom-0 left-3 right-3 h-[2px] bg-accent-strong" />
									)}
								</View>
							</TouchableOpacity>
						);
					})}
					<View className="flex-1" />
					<Text className="text-xs darker-text px-2">⌃⇥</Text>
				</View>
			)}

			{showResults && (
				<>
					<LoadingBar />
					<View className="flex-1 flex-row">
						<View className="flex-1 relative">
							<LegendList
								style={STYLES.list}
								contentContainerStyle={STYLES.contentContainer}
								ref={listRef}
								data={items}
								keyExtractor={(item) => item.id}
								renderItem={ItemRow}
								showsVerticalScrollIndicator={false}
								onLayout={(event) => {
									setListViewportHeight(event.nativeEvent.layout.height);
								}}
								onContentSizeChange={(_width, height) => {
									setListContentHeight(height);
								}}
								onScroll={(event) => {
									setListOffset(event.nativeEvent.contentOffset.y);
								}}
								scrollEventThrottle={16}
								ListEmptyComponent={
									<EmptyComponent
										message={
											activeTab === SearchTab.FILES && !store.ui.query
												? "Type to search files"
												: activeTab === SearchTab.FILES && store.ui.isLoading
													? "Searching…"
												: "No Results"
										}
									/>
								}
								recycleItems
								maintainVisibleContentPosition={false}
							/>
							{hasOverflow && (
								<View
									pointerEvents="none"
									className="absolute right-1.5 top-3 bottom-3 w-1 rounded-full bg-neutral-300/70 dark:bg-neutral-700/70"
								>
									<View
										className="w-1 rounded-full bg-neutral-600 dark:bg-neutral-300"
										style={{
											height: scrollThumbHeight,
											transform: [{ translateY: scrollThumbOffset }],
										}}
									/>
								</View>
							)}
						</View>
						{showNetworkPanel && <NetworkPanel />}
					</View>

					<View className="h-9 px-4 flex-row items-center justify-end gap-1 border-t border-color">
						{activeTab === SearchTab.FILES && (
							<>
								<FileSortControl upward />
								<View className="flex-1" />
							</>
						)}
						{store.ui.currentItem?.type === ItemType.CUSTOM && (
							<>
								<Text className="text-xs darker-text mr-1">Edit</Text>
								<Key symbol={"⌘"} />
								<Key symbol={"E"} />
								<View className="mx-2" />
								<Text className="text-xs darker-text mr-1">Delete</Text>
								<Key symbol={"⇧"} />
								<Key symbol={"⌫"} />
								<View className="mx-2" />
							</>
						)}
						<View className="mx-2" />
						<Text className="text-xs darker-text mr-1">
							{store.ui.currentItem?.type === ItemType.TEMPORARY_RESULT
								? (temporaryActionLabel ?? "Copy")
								: items.length
									? "Open"
									: activeTab === SearchTab.ALL
										? "Search the web"
										: "No result"}
						</Text>
						<Key symbol={"⏎"} primary />
						{!!store.ui.query && (
							<>
								<View className="mx-2" />
								<Text className="text-xs darker-text mr-1">AI</Text>
								<Key symbol={"⌃"} />
								<Key symbol={"⏎"} />
								<View className="mx-2" />
								<Text className="text-xs darker-text mr-1">Web</Text>
								<Key symbol={"⌘"} />
								<Key symbol={"⏎"} />
							</>
						)}
					</View>
				</>
			)}
		</View>
	);
});

const STYLES = StyleSheet.create({
	list: {
		flex: 1,
		marginTop: 4,
	},
	contentContainer: {
		flexGrow: 1,
		paddingHorizontal: 8,
		paddingVertical: 8,
	},
});
