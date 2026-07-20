import { Assets } from "assets";
import clsx from "clsx";
import { observer } from "mobx-react-lite";
import {
	DevSettings,
	Image,
	StyleSheet,
	Text,
	TouchableOpacity,
	View,
} from "react-native";
import { useStore } from "store";
import { Widget } from "stores/ui.store";
import { BackButton } from "./BackButton";
import { TextInput } from "./TextInput";

type Props = {
	placeholder?: string;
	showBackButton?: boolean;
	style?: any;
	className?: string;
	hideIcon?: boolean;
};

export const MainInput = observer<Props>(
	({ placeholder = "Search", showBackButton, hideIcon, className, style }) => {
		const store = useStore();
		const isDarkMode = store.ui.isDarkMode;
		const reloadApp = async () => {
			DevSettings.reload();
		};

		let leftButton = null;
		if (showBackButton) {
			leftButton = (
				<BackButton
					onPress={() => {
						store.ui.setQuery("");
						store.ui.focusWidget(Widget.SEARCH);
					}}
				/>
			);
		}

		if (!showBackButton) {
			leftButton = (
				<View className="w-8 h-8 items-center justify-center">
					<Image
						source={Assets.SearchIcon}
						style={{
							width: 24,
							height: 24,
							tintColor: isDarkMode ? "#FFFFFFB8" : "#00000082",
						}}
					/>
				</View>
			);
		}

		if (hideIcon) {
			leftButton = null;
		}

		return (
			<View
				className={`h-16 flex-row items-center gap-3 flex-1 px-4 ${className ?? ""}`}
				style={style}
			>
				{leftButton}
				<TextInput
					autoFocus
					multiline={false}
					enableFocusRing={false}
					value={store.ui.query}
					onChangeText={store.ui.setQuery}
					className={clsx("text-4xl font-light", {
						"text-white": isDarkMode,
						"text-black": !isDarkMode,
					})}
					style={STYLES.searchInput}
					textAlign="left"
					placeholder={placeholder}
					placeholderTextColor={isDarkMode ? "#FFFFFF66" : "#00000066"}
					clearButtonMode="while-editing"
				/>
				{__DEV__ && (
					<TouchableOpacity onPress={reloadApp}>
						<Text>Debug</Text>
					</TouchableOpacity>
				)}
			</View>
		);
	},
);

const STYLES = StyleSheet.create({
	searchInput: {
		flexBasis: 0,
		flexGrow: 1,
		flexShrink: 1,
		minWidth: 0,
	},
});
