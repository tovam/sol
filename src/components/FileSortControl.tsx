import { Dropdown } from "components/Dropdown";
import { observer } from "mobx-react-lite";
import { Text, View } from "react-native";
import { useStore } from "store";
import { FileSort } from "stores/ui.store";

const FILE_SORT_OPTIONS = [
	{ label: "Name A–Z", value: FileSort.NAME_ASC },
	{ label: "Name Z–A", value: FileSort.NAME_DESC },
	{ label: "Newest", value: FileSort.MODIFIED_DESC },
	{ label: "Oldest", value: FileSort.MODIFIED_ASC },
	{ label: "Largest", value: FileSort.SIZE_DESC },
	{ label: "Smallest", value: FileSort.SIZE_ASC },
];

export const FileSortControl = observer(
	({ upward = false }: { upward?: boolean }) => {
		const store = useStore();

		return (
			<View className="flex-row items-center gap-2 shrink-0">
				<Text className="text-xs darker-text">Sort</Text>
				<Dropdown
					value={store.ui.fileSort}
					onValueChange={(value) => store.ui.setFileSort(value as FileSort)}
					options={FILE_SORT_OPTIONS}
					searchable={false}
					upward={upward}
					className="h-7 py-0"
					style={{ width: 132 }}
				/>
			</View>
		);
	},
);
