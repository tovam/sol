import { LegendList, type LegendListRef } from "@legendapp/list/react-native";
import { Icons } from "assets";
import clsx from "clsx";
import Favicon from "components/Favicon";
import { FileIcon } from "components/FileIcon";
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
import { ItemType, Widget } from "stores/ui.store";
import type { TemporaryResult } from "stores/ui.store.helpers";

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

const ItemRow = observer(({ item, index }: { item: Item; index: number }) => {
	const store = useStore();
	const isActive = index === store.ui.selectedIndex;

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
				{item.isRunning && (
					<View
						className={clsx(
							"absolute bottom-1 left-[19px] h-[3px] w-[3px] rounded-full bg-neutral-600 dark:bg-neutral-400",
						)}
					/>
				)}
				{!!item.url && item.type !== ItemType.BOOKMARK && (
					<FileIcon url={item.url} className={"w-6 h-6"} />
				)}
				{item.type !== ItemType.CUSTOM && !!item.icon && (
					<Text>{item.icon}</Text>
				)}
				{item.type === ItemType.CUSTOM && !!item.icon && (
					<View className="w-6 h-6 rounded items-center justify-center bg-white dark:bg-black">
						<Image
							// @ts-expect-error
							source={Icons[item.icon]}
							style={{
								tintColor: item.color,
								height: 16,
								width: 16,
							}}
						/>
					</View>
				)}
				{!!item.iconImage && (
					<Image
						source={item.iconImage}
						className="w-6 h-6"
						resizeMode="contain"
					/>
				)}

				{item.type === ItemType.BOOKMARK && !!item.url && (
					<Favicon url={item.url} fallback={item.faviconFallback} />
				)}

				{(Platform.OS === "macos" || Platform.OS === "ios") &&
					!!item.IconComponent && <item.IconComponent />}
				<Text
					numberOfLines={1}
					className={clsx("ml-3 text max-w-xl", {
						"text-white": isActive,
					})}
				>
					{item.name}
				</Text>

				<View className="flex-1" />

				{item.type === ItemType.BOOKMARK && (
					<Text
						className={clsx("darker-text text-xs", {
							"text-white dark:text-neutral-200": isActive,
						})}
					>
						Browser Bookmark
					</Text>
				)}
				{item.type === ItemType.USER_SCRIPT && (
					<Text
						className={clsx("darker-text text-xs", {
							"text-white dark:text-neutral-200": isActive,
						})}
					>
						Script
					</Text>
				)}

				{item.type === ItemType.CUSTOM && (
					<Text
						className={clsx("darker-text text-xs", {
							"text-white dark:text-neutral-200": isActive,
						})}
					>
						Custom
					</Text>
				)}

				{!!item.subName && (
					<Text
						className={clsx("darker-text text-xs", {
							"text-white dark:text-white": isActive,
						})}
					>
						{item.subName}
					</Text>
				)}

				{item.type === ItemType.FILE && !!item.url && (
					<Text
						className={clsx("darker-text text-xs", {
							"text-white dark:text-white": isActive,
						})}
					>
						{item.url.slice(0, 45)}
					</Text>
				)}

				{!!store.ui.shortcuts[item.id] && (
					<View className="flex-row gap-1 items-center">
						{renderToKeys(store.ui.shortcuts[item.id])}
					</View>
				)}
				{item.type === ItemType.BOOKMARK && !!item.bookmarkFolder && (
					<Text className="flex-row gap-1 items-center">{`${item.bookmarkFolder.substring(
						0,
						16,
					)}${item.bookmarkFolder.length > 16 ? "..." : ""}`}</Text>
				)}
			</View>
		</TouchableOpacity>
	);
});

const EmptyComponent = () => {
	return (
		<View className="flex-1 items-center justify-center">
			<Text className="text-neutral-400 dark:text-neutral-500 text-base">
				No Results
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
	const showNetworkPanel = isNetworkQuery(store.ui.query);
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

	return (
		<View
			className={clsx({
				"flex-1": !!store.ui.query,
			})}
		>
			<View
				className={clsx("flex-row items-center", {
					"border-b border-color": !!store.ui.query,
				})}
			>
				<MainInput className="flex-1" />
			</View>

			{!!store.ui.query && (
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
								ListEmptyComponent={EmptyComponent}
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

					<View className="h-9 px-4 flex-row items-center justify-end gap-1 subBg border-t border-color">
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
									: "Search the web"}
						</Text>
						<Key symbol={"⏎"} primary />
						{!!items.length && (
							<>
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
