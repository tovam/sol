import { FileIcon } from "components/FileIcon";
import { TextInput } from "components/TextInput";
import { solNative } from "lib/SolNative";
import { observer } from "mobx-react-lite";
import { useMemo, useState } from "react";
import {
	ScrollView,
	Text,
	TouchableOpacity,
	View,
} from "react-native";
import { useStore } from "store";

const normalizeForSearch = (value: string) =>
	value
		.normalize("NFD")
		.replace(/[\u0300-\u036f]/g, "")
		.toLocaleLowerCase();

const containsWildcard = (path: string) => path.includes("*") || path.includes("?");

export const Applications = observer(() => {
	const store = useStore();
	const [path, setPath] = useState("");
	const [filter, setFilter] = useState("");
	const [isRefreshing, setIsRefreshing] = useState(false);
	const username = solNative.userName();
	const defaultLocations = [
		"/Applications",
		"/System/Applications",
		`/Users/${username}/Applications`,
	];

	const visibleApplications = useMemo(() => {
		const query = normalizeForSearch(filter.trim());
		return [...store.ui.apps]
			.filter((application) => {
				if (!query) return true;
				return normalizeForSearch(
					`${application.localizedName ?? application.name} ${application.name} ${application.url ?? ""}`,
				).includes(query);
			})
			.sort((left, right) =>
				(left.localizedName ?? left.name).localeCompare(
					right.localizedName ?? right.name,
					undefined,
					{ sensitivity: "base" },
				),
			);
	}, [filter, store.ui.apps]);

	const addPath = (candidate = path) => {
		if (!store.ui.addApplicationSearchPath(candidate)) {
			void solNative.showToast(
				"Use an absolute folder or wildcard path that is not already configured.",
				"error",
			);
			return;
		}
		setPath("");
	};

	const chooseFolder = async () => {
		try {
			solNative.hideWindow();
			const selectedDirectory = await solNative.openFilePicker();
			if (selectedDirectory) addPath(selectedDirectory);
		} catch {
			// The native picker rejects when the user cancels.
		} finally {
			solNative.showWindow();
		}
	};

	const refresh = async () => {
		setIsRefreshing(true);
		try {
			await store.ui.getApps();
		} finally {
			setIsRefreshing(false);
		}
	};

	return (
		<ScrollView
			showsVerticalScrollIndicator
			className="flex-1"
			contentContainerClassName="p-3 gap-2"
		>
			<View className="p-2.5 subBg gap-2 rounded-lg border border-lightBorder dark:border-darkBorder">
				<View>
					<Text className="text-sm font-semibold text">Search locations</Text>
					<Text className="text-xxs darker-text mt-0.5">
						The macOS application folders stay enabled. Add a folder, or a
						wildcard path for an unusual layout.
					</Text>
				</View>

				<View className="flex-row items-center gap-2">
					<TextInput
						enableFocusRing={false}
						autoCapitalize="none"
						autoCorrect={false}
						multiline={false}
						className="flex-1 text-sm text px-3 py-1.5 rounded-md border border-color"
						style={{ textAlign: "left" }}
						value={path}
						onChangeText={setPath}
						onSubmitEditing={() => addPath()}
						placeholder="/Volumes/*/Applications or ~/Tools/**/*.app"
					/>
					<TouchableOpacity
						disabled={!path.trim()}
						className="px-2.5 py-1.5 rounded-md bg-accent-strong"
						onPress={() => addPath()}
					>
						<Text className="text-xs font-semibold text-white">Add path</Text>
					</TouchableOpacity>
					<TouchableOpacity
						className="px-2.5 py-1.5 rounded-md border border-color"
						onPress={() => void chooseFolder()}
					>
						<Text className="text-xs font-semibold text">Choose folder</Text>
					</TouchableOpacity>
				</View>

				<Text className="text-xxs darker-text">
					* matches within one folder, ? matches one character, and ** crosses
					any number of subfolders. Wildcard names ignore case.
				</Text>

				<View className="border-t border-color" />
				{defaultLocations.map((location) => (
					<View key={location} className="flex-row items-center gap-2 py-1">
						<View className="w-2 h-2 rounded-full bg-green-500" />
						<Text className="flex-1 text-xs text" numberOfLines={1}>
							{location}
						</Text>
						<Text className="text-xxs darker-text">macOS default</Text>
					</View>
				))}

				{store.ui.applicationSearchPaths.map((searchPath) => (
					<View
						key={searchPath}
						className="flex-row items-center gap-2 py-1 border-t border-color"
					>
						<View className="w-2 h-2 rounded-full bg-accent-strong" />
						<Text className="flex-1 text-xs text" numberOfLines={1}>
							{searchPath}
						</Text>
						<Text className="text-xxs darker-text">
							{containsWildcard(searchPath) ? "Wildcard" : "Folder"}
						</Text>
						<TouchableOpacity
							className="px-2 py-1"
							onPress={() =>
								store.ui.removeApplicationSearchPath(searchPath)
							}
						>
							<Text className="text-xs text-red-500">Remove</Text>
						</TouchableOpacity>
					</View>
				))}
			</View>

			<View className="p-2.5 subBg gap-2 rounded-lg border border-lightBorder dark:border-darkBorder">
				<View className="flex-row items-center gap-2">
					<View className="flex-1">
						<Text className="text-sm font-semibold text">
							Detected applications ({store.ui.apps.length})
						</Text>
						<Text className="text-xxs darker-text">
							This is the same application list used by the launcher.
						</Text>
					</View>
					<TouchableOpacity className="px-2 py-1" onPress={() => void refresh()}>
						<Text className="text-xs text-accent">
							{isRefreshing ? "Refreshing…" : "Refresh"}
						</Text>
					</TouchableOpacity>
				</View>

				<TextInput
					enableFocusRing={false}
					multiline={false}
					className="w-full text-sm text px-3 py-1.5 rounded-md border border-color"
					style={{ textAlign: "left" }}
					value={filter}
					onChangeText={setFilter}
					placeholder="Filter by name or path"
				/>

				{visibleApplications.length === 0 ? (
					<Text className="text-xs italic darker-text py-2">
						{filter.trim() ? "No matching application." : "No application found."}
					</Text>
				) : (
					visibleApplications.map((application) => (
						<View
							key={application.id}
							className="flex-row items-center gap-2 py-1.5 border-t border-color"
						>
							<View className="relative w-7 h-7 items-center justify-center">
								<FileIcon url={application.url} className="w-6 h-6" />
								{application.isRunning && (
									<View className="absolute right-0 top-0 w-2 h-2 rounded-full bg-green-600 border border-white dark:border-neutral-800" />
								)}
							</View>
							<View className="flex-1">
								<Text className="text-xs font-medium text" numberOfLines={1}>
									{application.localizedName ?? application.name}
								</Text>
								<Text className="text-xxs darker-text" numberOfLines={1}>
									{application.url}
								</Text>
							</View>
						</View>
					))
				)}
			</View>
		</ScrollView>
	);
});
