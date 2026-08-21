import { TextInput } from "components/TextInput";
import { solNative, type FloatingSpreadsheetSummary } from "lib/SolNative";
import { observer } from "mobx-react-lite";
import { useEffect, useState } from "react";
import { ScrollView, Text, TouchableOpacity, View } from "react-native";
import { useStore } from "store";

const formatDate = (timestamp?: number) => {
	if (!timestamp) return "Unknown date";
	return new Date(timestamp).toLocaleString(undefined, {
		dateStyle: "medium",
		timeStyle: "short",
	});
};

const SpreadsheetIcon = () => (
	<View className="w-7 h-7 rounded-md items-center justify-center bg-black/5 dark:bg-white/5">
		<Text className="text-base text">▦</Text>
	</View>
);

const SpreadsheetMetadata = ({
	spreadsheet,
	archived,
}: {
	spreadsheet: FloatingSpreadsheetSummary;
	archived?: boolean;
}) => (
	<Text className="text-xxs darker-text" numberOfLines={1}>
		{archived
			? `Archived ${formatDate(spreadsheet.archivedAt)}`
			: `Updated ${formatDate(spreadsheet.updatedAt)}`}
		{" · "}
		{spreadsheet.cellCount} cells · {spreadsheet.chartCount} charts
		{!archived && spreadsheet.scheduledArchiveAt
			? ` · Auto-archive ${formatDate(spreadsheet.scheduledArchiveAt)}`
			: ""}
	</Text>
);

export const SpreadsheetsSettings = observer(() => {
	const store = useStore();
	const spreadsheets = store.spreadsheets;
	const [editingID, setEditingID] = useState<string | null>(null);
	const [draftName, setDraftName] = useState("");

	const refreshAll = () =>
		Promise.all([spreadsheets.refresh(), spreadsheets.refreshArchived()]);

	useEffect(() => {
		void refreshAll();
	}, []);

	const beginRename = (spreadsheet: FloatingSpreadsheetSummary) => {
		setEditingID(spreadsheet.id);
		setDraftName(spreadsheet.name);
	};

	const cancelRename = () => {
		setEditingID(null);
		setDraftName("");
	};

	const saveRename = async () => {
		const identifier = editingID;
		const name = draftName.trim();
		if (!identifier || !name) return;
		await spreadsheets.rename(identifier, name);
		cancelRename();
	};

	const createSpreadsheet = () => {
		solNative.hideWindow();
		void spreadsheets.create();
	};

	const refreshing = spreadsheets.isLoading || spreadsheets.isLoadingArchived;

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
							Active spreadsheets ({spreadsheets.summaries.length})
						</Text>
						<Text className="text-xxs darker-text mt-0.5">
							Open, rename, archive or permanently delete saved spreadsheets.
						</Text>
					</View>
					<TouchableOpacity className="px-2 py-1" onPress={() => void refreshAll()}>
						<Text className="text-xs text-accent">
							{refreshing ? "Refreshing…" : "Refresh"}
						</Text>
					</TouchableOpacity>
					<TouchableOpacity
						className="px-2.5 py-1.5 rounded-md bg-accent-strong"
						onPress={createSpreadsheet}
					>
						<Text className="text-xs font-semibold text-white">New</Text>
					</TouchableOpacity>
				</View>

				{!spreadsheets.isLoading && spreadsheets.summaries.length === 0 ? (
					<Text className="text-xs italic darker-text py-2">
						No active spreadsheet.
					</Text>
				) : (
					spreadsheets.summaries.map((spreadsheet) => {
						const editing = editingID === spreadsheet.id;
						return (
							<View
								key={spreadsheet.id}
								className="flex-row items-center gap-2 py-2 border-t border-color"
							>
								<SpreadsheetIcon />
								<View className="flex-1">
									{editing ? (
										<TextInput
											enableFocusRing={false}
											multiline={false}
											autoFocus
											className="w-full text-xs text px-2 py-1 rounded-md border border-color"
											style={{ textAlign: "left" }}
											value={draftName}
											onChangeText={setDraftName}
											onSubmitEditing={() => void saveRename()}
										/>
									) : (
										<Text className="text-xs font-medium text" numberOfLines={1}>
											{spreadsheet.name}
										</Text>
									)}
									<SpreadsheetMetadata spreadsheet={spreadsheet} />
								</View>

								{editing ? (
									<>
										<TouchableOpacity
											disabled={!draftName.trim()}
											className="px-2.5 py-1.5 rounded-md bg-accent-strong"
											onPress={() => void saveRename()}
										>
											<Text className="text-xs font-semibold text-white">Save</Text>
										</TouchableOpacity>
										<TouchableOpacity className="px-2 py-1.5" onPress={cancelRename}>
											<Text className="text-xs text">Cancel</Text>
										</TouchableOpacity>
									</>
								) : (
									<>
										<TouchableOpacity
											className="px-2 py-1.5"
											onPress={() => void spreadsheets.open(spreadsheet.id)}
										>
											<Text className="text-xs text-accent">Open</Text>
										</TouchableOpacity>
										<TouchableOpacity
											className="px-2 py-1.5"
											onPress={() => beginRename(spreadsheet)}
										>
											<Text className="text-xs text">Rename</Text>
										</TouchableOpacity>
										<TouchableOpacity
											className="px-2 py-1.5"
											onPress={() =>
												store.ui.confirm(`Archive “${spreadsheet.name}” now?`, () =>
													void spreadsheets.archive(spreadsheet.id),
												)
											}
										>
											<Text className="text-xs text">Archive</Text>
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
									</>
								)}
							</View>
						);
					})
				)}
			</View>

			<View className="p-2.5 subBg gap-2 rounded-lg border border-lightBorder dark:border-darkBorder">
				<View>
					<Text className="text-sm font-semibold text">
						Archived spreadsheets ({spreadsheets.archivedSummaries.length})
					</Text>
					<Text className="text-xxs darker-text mt-0.5">
						Archived spreadsheets are excluded from every launcher alias and can
						only be recovered here.
					</Text>
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
							<SpreadsheetIcon />
							<View className="flex-1">
								<Text className="text-xs font-medium text" numberOfLines={1}>
									{spreadsheet.name}
								</Text>
								<SpreadsheetMetadata spreadsheet={spreadsheet} archived />
							</View>
							<TouchableOpacity
								className="px-2.5 py-1.5 rounded-md bg-accent-strong"
								onPress={() => void spreadsheets.restore(spreadsheet.id)}
							>
								<Text className="text-xs font-semibold text-white">Restore & open</Text>
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
