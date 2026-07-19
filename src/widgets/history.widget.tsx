import { LegendList, type LegendListRef } from "@legendapp/list/react-native";
import clsx from "clsx";
import { Key } from "components/Key";
import { MainInput } from "components/MainInput";
import { observer } from "mobx-react-lite";
import { type FC, useEffect, useRef } from "react";
import { StyleSheet, Text, TouchableOpacity, View } from "react-native";
import { useStore } from "store";

const HistoryRow = observer(
	({ query, index }: { query: string; index: number }) => {
		const store = useStore();
		const isActive = index === store.ui.selectedIndex;

		return (
			<TouchableOpacity
				onPress={() => {
					store.ui.setSelectedIndex(index);
					store.keystroke.simulateEnter();
				}}
			>
				<View
					className={clsx("h-12 px-4 rounded-xl flex-row items-center", {
						"bg-accent-strong": isActive,
					})}
				>
					<View className="w-8 h-8 items-center justify-center">
						<Text
							className={clsx("text-lg darker-text", {
								"text-white dark:text-neutral-200": isActive,
							})}
						>
							↺
						</Text>
					</View>
					<Text
						numberOfLines={1}
						className={clsx("ml-3 text flex-1", {
							"text-white": isActive,
						})}
					>
						{query}
					</Text>
					<Text
						className={clsx("text-xs darker-text", {
							"text-white dark:text-neutral-200": isActive,
						})}
					>
						Previous search
					</Text>
				</View>
			</TouchableOpacity>
		);
	},
);

export const HistoryWidget: FC = observer(() => {
	const store = useStore();
	const entries = store.ui.filteredHistory;
	const selectedIndex = store.ui.selectedIndex;
	const listRef = useRef<LegendListRef | null>(null);

	useEffect(() => {
		if (entries.length && selectedIndex < entries.length) {
			listRef.current?.scrollToIndex({
				index: selectedIndex,
				viewOffset: 64,
			});
		}
	}, [entries.length, selectedIndex]);

	return (
		<View className="flex-1">
			<View className="flex-row border-b border-color">
				<MainInput placeholder="Search history..." showBackButton />
			</View>
			<LegendList
				ref={listRef}
				data={entries}
				className="flex-1"
				contentContainerStyle={STYLES.contentContainer}
				keyExtractor={(query, index) => `${index}-${query}`}
				renderItem={({ item, index }) => (
					<HistoryRow query={item} index={index} />
				)}
				ListEmptyComponent={
					<View className="flex-1 items-center justify-center">
						<Text className="darker-text text-sm">No previous searches</Text>
					</View>
				}
				showsVerticalScrollIndicator={false}
			/>
			{entries.length > 0 && (
				<View className="h-9 px-4 flex-row items-center justify-end gap-1 subBg border-t border-color">
					<Text className="text-xs darker-text mr-1">Use search</Text>
					<Key symbol="⏎" primary />
				</View>
			)}
		</View>
	);
});

const STYLES = StyleSheet.create({
	contentContainer: {
		flexGrow: 1,
		paddingHorizontal: 8,
		paddingVertical: 8,
	},
});
