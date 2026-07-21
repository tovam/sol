import { Assets } from "assets";
import clsx from "clsx";
import { useBoolean } from "hooks";
import {
	Image,
	ScrollView,
	Text,
	TouchableOpacity,
	useColorScheme,
	View,
	type ViewStyle,
} from "react-native";
import { SelectableButton } from "./SelectableButton";
import { TextInput } from "./TextInput";
import { useEffect, useMemo, useState } from "react";
import MiniSearch from "minisearch";

interface Props<T> {
	value: T;
	style?: ViewStyle;
	containerStyle?: ViewStyle;
	className?: string;
	onValueChange: (t: T) => void;
	options: Array<{
		label: string;
		value: T;
	}>;
	upward?: boolean;
	disabled?: boolean;
	placeholder?: string;
	searchable?: boolean;
}

export const Dropdown = ({
	value,
	style,
	containerStyle,
	className,
	options,
	onValueChange,
	upward = false,
	disabled = false,
	placeholder = "Select…",
	searchable = true,
}: Props<string | number>) => {
	const [isOpen, open, close] = useBoolean();
	const [isHovered, hoverOn, hoverOff] = useBoolean();
	const colorScheme = useColorScheme();
	const [x, setX] = useState(0);
	const [y, setY] = useState(0);
	const [width, setWidth] = useState(0);
	const [height, setHeight] = useState(0);
	const [searchQuery, setSearchQuery] = useState("");

	useEffect(() => {
		if (disabled && isOpen) {
			close();
			setSearchQuery("");
		}
	}, [disabled, isOpen]);

	const miniSearch = useMemo(() => {
		const search = new MiniSearch({
			fields: ["label"],
			storeFields: ["label", "value"],
			searchOptions: {
				prefix: true,
				fuzzy: 0.2,
			},
		});
		search.addAll(options.map((opt, idx) => ({ id: idx, ...opt })));
		return search;
	}, [options]);

	const filteredOptions = useMemo(() => {
		if (!searchQuery.trim()) {
			return options;
		}
		const results = miniSearch.search(searchQuery);
		return results.map((result) => {
			const item = result as unknown as {
				label: string;
				value: string | number;
			};
			return {
				label: item.label,
				value: item.value,
			};
		});
	}, [searchQuery, options, miniSearch]);

	return (
		<View style={[{ zIndex: isOpen ? 1000 : 0 }, containerStyle]}>
			<TouchableOpacity
				onLayout={(e) => {
					const {
						x: layoutX,
						y: layoutY,
						width: layoutWidth,
						height: layoutHeight,
					} = e.nativeEvent.layout;
					setX(layoutX);
					setY(layoutY);
					setHeight(layoutHeight);
					setWidth(layoutWidth);
				}}
				// @ts-expect-error
				onMouseEnter={hoverOn}
				onMouseLeave={hoverOff}
				enableFocusRing={false}
				disabled={disabled}
				onPress={() => {
					if (isOpen) {
						close();
						setSearchQuery("");
					} else {
						open();
					}
				}}
				className={clsx(
					"w-48 rounded justify-center items-center border flex-row py-1 border-neutral-300 dark:border-neutral-700",
					className,
					{
						"dark:bg-neutral-700": isHovered,
						"border-accent": isOpen,
						"opacity-50": disabled,
					},
				)}
				style={style}
			>
				<Text className="flex-1 text-sm text ml-2" numberOfLines={1}>
					{options.find((o) => o.value === value)?.label ?? placeholder}
				</Text>
				<Image
					source={isOpen ? Assets.ChevronUp : Assets.ChevronDown}
					className="h-4 w-4 mr-2"
					style={{
						tintColor: colorScheme === "dark" ? "#777" : "black",
					}}
				/>
			</TouchableOpacity>
			{isOpen && (
				<View
					className={clsx(
						"w-48 rounded border border-neutral-300 dark:border-neutral-700 bg-white dark:bg-neutral-800 absolute",
					)}
					style={{
						top: upward ? undefined : y + height + 1,
						bottom: upward ? height + 1 : undefined,
						left: x,
						width: width,
						zIndex: 1000,
					}}
				>
					{searchable && (
						<TextInput
							className="px-3 py-2 text-sm border-b border-neutral-300 dark:border-neutral-700 dark:text-white"
							placeholder="Search..."
							placeholderTextColor={colorScheme === "dark" ? "#777" : "#999"}
							value={searchQuery}
							onChangeText={setSearchQuery}
							autoFocus
						/>
					)}
					<ScrollView
						className="max-h-32"
						contentContainerClassName="gap-1 py-1 px-1.5"
						showsVerticalScrollIndicator={false}
					>
						{filteredOptions.length === 0 && (
							<Text className="px-2 py-3 text-xs text-center darker-text">
								No matching model
							</Text>
						)}
						{filteredOptions.map((o, i) => (
							<SelectableButton
								title={o.label}
								key={`${String(o.value)}-${i}`}
								selected={false}
								onPress={() => {
									if (disabled) return;
									onValueChange(o.value);
									setSearchQuery("");
									close();
								}}
							/>
						))}
					</ScrollView>
				</View>
			)}
		</View>
	);
};
