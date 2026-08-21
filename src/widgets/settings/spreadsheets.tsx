import { observer } from "mobx-react-lite";
import { useEffect } from "react";
import { ScrollView, Text, TouchableOpacity, View } from "react-native";
import { useStore } from "store";

const formatDate = (timestamp?: number) => {
	if (!timestamp) return "Unknown date";
	return new Date(timestamp).toLocaleString(undefined, {
		dateStyle: "medium",
		timeStyle: "short",
	});
};

export const SpreadsheetsSettings = observer(() => {
	const store = useStore();
	const spreadsheets = store.spreadsheets;

	useEffect(() => {
		void spreadsheets.refreshArchived();
	}, [spreadsheets]);

	return (
		<ScrollView
			showsVerticalScrollIndicator
			className="flex-1"
			contentContainerClassName="p-3 gap-2"
		>
			<View className="p-2.5 subBg gap-2 rounded-lg border border-lightBorder dark:border-darkBorder">
				<View className="flex-row items-center gap-2">
					<View className="flex-1">
						<Text className="text-sm font-semibold text">
							Archived spreadsheets ({spreadsheets.archivedSummaries.length})
						</Text>
						<Text className="text-xxs darker-text mt-0.5">
							Expired spreadsheets disappear from Sol search and remain recoverable
							only here.
						</Text>
					</View>
					<TouchableOpacity
						className="px-2 py-1"
						onPress={() => void spreadsheets.refreshArchived()}
					>
						<Text className="text-xs text-accent">
							{spreadsheets.isLoadingArchived ? "Refreshing…" : "Refresh"}
						</Text>
					</TouchableOpacity>
				</View>

				{!spreadsheets.isLoadingArchived &&
				spreadsheets.archivedSummaries.length === 0 ? (
					<Text className="text-xs italic darker-text py-2">
						No archived spreadsheet.
					</Text>
				) : (
					spreadsheets.archivedSummaries.map((spreadsheet) => (
						<View
							key={spreadsheet.id}
							className="flex-row items-center gap-2 py-2 border-t border-color"
						>
							<View className="w-7 h-7 rounded-md items-center justify-center bg-black/5 dark:bg-white/5">
								<Text className="text-base text">▦</Text>
							</View>
							<View className="flex-1">
								<Text className="text-xs font-medium text" numberOfLines={1}>
									{spreadsheet.name}
								</Text>
								<Text className="text-xxs darker-text" numberOfLines={1}>
									Archived {formatDate(spreadsheet.archivedAt)} · {spreadsheet.cellCount}{" "}
									cells · {spreadsheet.chartCount} charts
								</Text>
							</View>
							<TouchableOpacity
								className="px-2.5 py-1.5 rounded-md bg-accent-strong"
								onPress={() => void spreadsheets.restore(spreadsheet.id)}
							>
								<Text className="text-xs font-semibold text-white">Restore</Text>
							</TouchableOpacity>
							<TouchableOpacity
								className="px-2 py-1.5"
								onPress={() =>
									store.ui.confirm(
										`Permanently delete “${spreadsheet.name}”?`,
										() => void spreadsheets.delete(spreadsheet.id),
									)
								}
							>
								<Text className="text-xs text-red-500">Delete</Text>
							</TouchableOpacity>
						</View>
					))
				)}
			</View>
		</ScrollView>
	);
});
