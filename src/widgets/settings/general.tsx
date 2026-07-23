import { Assets } from "assets";
import clsx from "clsx";
import { Dropdown } from "components/Dropdown";
import { Input } from "components/Input";
import { MySwitch } from "components/MySwitch";
import { type SearchWindowAnimation, solNative } from "lib/SolNative";
import { observer } from "mobx-react-lite";
import { useEffect, useState } from "react";
import { Image, ScrollView, Text, TouchableOpacity, View } from "react-native";
import { useStore } from "store";

export const isValidCustomSearchEngineUrl = (url: string) => {
	if (url.trim() === "") return false;
	const searchPatternRegex =
		/^https?:\/\/(?:(?:[a-zA-Z0-9](?:[a-zA-Z0-9-]*[a-zA-Z0-9])?\.)+[a-zA-Z0-9](?:[a-zA-Z0-9-]*[a-zA-Z0-9])?|localhost|\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3})(:\d+)?(\/[^\s?#]*)?\?[\w-]+=%s$/;
	return searchPatternRegex.test(url);
};

const GlassAppearanceSettings = observer(() => {
	const store = useStore();
	const appearance = store.ui.glassAppearance;
	const [style, setStyle] = useState<"clear" | "regular">(appearance.style);
	const [cornerRadius, setCornerRadius] = useState(
		String(appearance.cornerRadius),
	);
	const [tintColor, setTintColor] = useState(appearance.tintColor ?? "");
	const [tintOpacity, setTintOpacity] = useState(
		String(Math.round(appearance.tintOpacity * 100)),
	);
	const [shadowOpacity, setShadowOpacity] = useState(
		String(Math.round(appearance.shadowOpacity * 100)),
	);
	const [shadowRadius, setShadowRadius] = useState(
		String(appearance.shadowRadius),
	);
	const [shadowOffsetY, setShadowOffsetY] = useState(
		String(appearance.shadowOffsetY),
	);

	useEffect(() => {
		setStyle(appearance.style);
		setCornerRadius(String(appearance.cornerRadius));
		setTintColor(appearance.tintColor ?? "");
		setTintOpacity(String(Math.round(appearance.tintOpacity * 100)));
		setShadowOpacity(String(Math.round(appearance.shadowOpacity * 100)));
		setShadowRadius(String(appearance.shadowRadius));
		setShadowOffsetY(String(appearance.shadowOffsetY));
	}, [
		appearance.style,
		appearance.cornerRadius,
		appearance.tintColor,
		appearance.tintOpacity,
		appearance.shadowOpacity,
		appearance.shadowRadius,
		appearance.shadowOffsetY,
	]);

	const parsedRadius = Number(cornerRadius.replace(",", "."));
	const parsedOpacity = Number(tintOpacity.replace(",", "."));
	const parsedShadowOpacity = Number(shadowOpacity.replace(",", "."));
	const parsedShadowRadius = Number(shadowRadius.replace(",", "."));
	const parsedShadowOffsetY = Number(shadowOffsetY.replace(",", "."));
	const normalizedTint = tintColor.trim();
	const tintIsValid =
		normalizedTint === "" || /^#[\dA-Fa-f]{6}$/.test(normalizedTint);
	const valuesAreValid =
		cornerRadius.trim() !== "" &&
		tintOpacity.trim() !== "" &&
		Number.isFinite(parsedRadius) &&
		parsedRadius >= 0 &&
		parsedRadius <= 32 &&
		Number.isFinite(parsedOpacity) &&
		parsedOpacity >= 0 &&
		parsedOpacity <= 100 &&
		shadowOpacity.trim() !== "" &&
		Number.isFinite(parsedShadowOpacity) &&
		parsedShadowOpacity >= 0 &&
		parsedShadowOpacity <= 100 &&
		shadowRadius.trim() !== "" &&
		Number.isFinite(parsedShadowRadius) &&
		parsedShadowRadius >= 0 &&
		parsedShadowRadius <= 32 &&
		shadowOffsetY.trim() !== "" &&
		Number.isFinite(parsedShadowOffsetY) &&
		parsedShadowOffsetY >= -16 &&
		parsedShadowOffsetY <= 16 &&
		tintIsValid;

	const reset = () => {
		setStyle("clear");
		setCornerRadius("24");
		setTintColor("");
		setTintOpacity("0");
		setShadowOpacity("32");
		setShadowRadius("12");
		setShadowOffsetY("3");
		store.ui.resetGlassAppearance();
	};

	return (
		<View className="z-30 p-2.5 subBg gap-2 rounded-lg border border-lightBorder dark:border-darkBorder">
			<View>
				<Text className="text-sm text">Window Glass</Text>
				<Text className="text-xxs text-neutral-500 dark:text-neutral-400 mt-1">
					These are the public Liquid Glass controls. Blur and refraction stay
					adaptive and are managed by macOS.
				</Text>
			</View>

			<View className="border-t border-lightBorder dark:border-darkBorder" />

			<View className="flex-row items-center z-40">
				<View className="flex-1">
					<Text className="text-sm text">Style</Text>
					<Text className="text-xxs text-neutral-500 dark:text-neutral-400">
						Clear lets more of the background through
					</Text>
				</View>
				<Dropdown
					value={style}
					onValueChange={(value) =>
						setStyle(value === "regular" ? "regular" : "clear")
					}
					options={[
						{ label: "Clear", value: "clear" },
						{ label: "Regular", value: "regular" },
					]}
				/>
			</View>

			<View className="flex-row items-center gap-2">
				<View className="flex-1">
					<Text className="text-sm text">Corner radius</Text>
					<Text className="text-xxs text-neutral-500 dark:text-neutral-400">
						0–32 pt; 32 pt makes the collapsed bar a capsule
					</Text>
				</View>
				<Input
					bordered
					className="w-20 h-7"
					inputClassName="text-right"
					value={cornerRadius}
					onChangeText={setCornerRadius}
				/>
				<Text className="text-xs darker-text w-5">pt</Text>
			</View>

			<View className="flex-row items-center gap-2">
				<View className="flex-1">
					<Text className="text-sm text">Tint color</Text>
					<Text className="text-xxs text-neutral-500 dark:text-neutral-400">
						#RRGGBB, or leave empty for adaptive glass
					</Text>
				</View>
				<Input
					bordered
					className="w-32 h-7"
					inputClassName="text-right"
					placeholder="#FFFFFF"
					value={tintColor}
					onChangeText={setTintColor}
				/>
			</View>

			<View className="flex-row items-center gap-2">
				<View className="flex-1">
					<Text className="text-sm text">Tint intensity</Text>
					<Text className="text-xxs text-neutral-500 dark:text-neutral-400">
						Used with a tint color; start below 20% for a subtle result
					</Text>
				</View>
				<Input
					bordered
					className="w-20 h-7"
					inputClassName="text-right"
					value={tintOpacity}
					onChangeText={setTintOpacity}
					readOnly={normalizedTint === ""}
				/>
				<Text className="text-xs darker-text w-5">%</Text>
			</View>

			<View className="border-t border-lightBorder dark:border-darkBorder" />

			<View>
				<Text className="text-sm text">Shadow</Text>
				<Text className="text-xxs text-neutral-500 dark:text-neutral-400 mt-1">
					A subtle black shadow separates the glass from the background
				</Text>
			</View>

			<View className="flex-row items-center gap-2">
				<View className="flex-1">
					<Text className="text-sm text">Opacity</Text>
					<Text className="text-xxs text-neutral-500 dark:text-neutral-400">
						0–100%; Spotlight-like starts around 30%
					</Text>
				</View>
				<Input
					bordered
					className="w-20 h-7"
					inputClassName="text-right"
					value={shadowOpacity}
					onChangeText={setShadowOpacity}
				/>
				<Text className="text-xs darker-text w-5">%</Text>
			</View>

			<View className="flex-row items-center gap-2">
				<View className="flex-1">
					<Text className="text-sm text">Blur radius</Text>
					<Text className="text-xxs text-neutral-500 dark:text-neutral-400">
						0–32 pt; controls the shadow size and softness
					</Text>
				</View>
				<Input
					bordered
					className="w-20 h-7"
					inputClassName="text-right"
					value={shadowRadius}
					onChangeText={setShadowRadius}
				/>
				<Text className="text-xs darker-text w-5">pt</Text>
			</View>

			<View className="flex-row items-center gap-2">
				<View className="flex-1">
					<Text className="text-sm text">Vertical offset</Text>
					<Text className="text-xxs text-neutral-500 dark:text-neutral-400">
						−16–16 pt; positive values move the shadow down
					</Text>
				</View>
				<Input
					bordered
					className="w-20 h-7"
					inputClassName="text-right"
					value={shadowOffsetY}
					onChangeText={setShadowOffsetY}
				/>
				<Text className="text-xs darker-text w-5">pt</Text>
			</View>

			{!valuesAreValid && (
				<Text className="text-xs text-red-500">
					Check the ranges above and use a valid #RRGGBB tint color.
				</Text>
			)}

			<View className="flex-row justify-end gap-2">
				<TouchableOpacity onPress={reset}>
					<View className="px-3 py-1.5 rounded-md border border-color">
						<Text className="text-xs text">Reset</Text>
					</View>
				</TouchableOpacity>
				<TouchableOpacity
					disabled={!valuesAreValid}
					onPress={() => {
						if (!valuesAreValid) return;
						store.ui.setGlassAppearance({
							style,
							cornerRadius: parsedRadius,
							tintColor: normalizedTint || null,
							tintOpacity: normalizedTint ? parsedOpacity / 100 : 0,
							shadowOpacity: parsedShadowOpacity / 100,
							shadowRadius: parsedShadowRadius,
							shadowOffsetY: parsedShadowOffsetY,
						});
					}}
				>
					<View
						className={clsx("px-3 py-1.5 rounded-md", {
							"bg-accent-strong": valuesAreValid,
							"bg-neutral-300 dark:bg-neutral-700": !valuesAreValid,
						})}
					>
						<Text className="text-xs text-white">Apply</Text>
					</View>
				</TouchableOpacity>
			</View>

			<Text className="text-xxs text-neutral-500 dark:text-neutral-400">
				Saved as glassAppearance in ~/.config/sol/config.json. Requires macOS 26
				for native Liquid Glass; older versions use a visual-effect fallback.
			</Text>
		</View>
	);
});

type SearchWindowAnimationDraft = Record<keyof SearchWindowAnimation, string>;

const createSearchWindowAnimationDraft = (
	animation: SearchWindowAnimation,
): SearchWindowAnimationDraft => ({
	openingWidthExtra: String(animation.openingWidthExtra),
	openingHeightExtraPercent: String(animation.openingHeightExtraPercent),
	openingDurationMs: String(animation.openingDurationMs),
	openingBounce: String(Math.round(animation.openingBounce * 100)),
	openingInitialOpacity: String(
		Math.round(animation.openingInitialOpacity * 100),
	),
	closingWidthExtraPercent: String(animation.closingWidthExtraPercent),
	closingHeightExtraPercent: String(animation.closingHeightExtraPercent),
	closingDurationMs: String(animation.closingDurationMs),
	resultsExpandDurationMs: String(animation.resultsExpandDurationMs),
	resultsCollapseDurationMs: String(animation.resultsCollapseDurationMs),
});

const AnimationNumberRow = ({
	title,
	description,
	value,
	onChangeText,
	unit,
}: {
	title: string;
	description: string;
	value: string;
	onChangeText: (value: string) => void;
	unit: string;
}) => (
	<View className="flex-row items-center gap-2">
		<View className="flex-1">
			<Text className="text-sm text">{title}</Text>
			<Text className="text-xxs text-neutral-500 dark:text-neutral-400">
				{description}
			</Text>
		</View>
		<Input
			bordered
			className="w-20 h-7"
			inputClassName="text-right"
			value={value}
			onChangeText={onChangeText}
		/>
		<Text className="text-xs darker-text w-7">{unit}</Text>
	</View>
);

const SearchWindowAnimationSettings = observer(() => {
	const store = useStore();
	const animation = store.ui.searchWindowAnimation;
	const [draft, setDraft] = useState<SearchWindowAnimationDraft>(() =>
		createSearchWindowAnimationDraft(animation),
	);

	useEffect(() => {
		setDraft(createSearchWindowAnimationDraft(animation));
	}, [animation]);

	const updateDraft = (key: keyof SearchWindowAnimation, value: string) => {
		setDraft((current) => ({ ...current, [key]: value }));
	};
	const draftNumber = (key: keyof SearchWindowAnimation) =>
		Number(draft[key].replace(",", "."));
	const ranges: Array<[keyof SearchWindowAnimation, number, number]> = [
		["openingWidthExtra", 0, 200],
		["openingHeightExtraPercent", 0, 20],
		["openingDurationMs", 0, 1000],
		["openingBounce", 0, 100],
		["openingInitialOpacity", 0, 100],
		["closingWidthExtraPercent", 0, 20],
		["closingHeightExtraPercent", 0, 20],
		["closingDurationMs", 0, 1000],
		["resultsExpandDurationMs", 0, 1000],
		["resultsCollapseDurationMs", 0, 1000],
	];
	const valuesAreValid = ranges.every(([key, minimum, maximum]) => {
		const value = draftNumber(key);
		return (
			draft[key].trim() !== "" &&
			Number.isFinite(value) &&
			value >= minimum &&
			value <= maximum
		);
	});

	const apply = () => {
		if (!valuesAreValid) return;
		store.ui.setSearchWindowAnimation({
			openingWidthExtra: draftNumber("openingWidthExtra"),
			openingHeightExtraPercent: draftNumber("openingHeightExtraPercent"),
			openingDurationMs: draftNumber("openingDurationMs"),
			openingBounce: draftNumber("openingBounce") / 100,
			openingInitialOpacity: draftNumber("openingInitialOpacity") / 100,
			closingWidthExtraPercent: draftNumber("closingWidthExtraPercent"),
			closingHeightExtraPercent: draftNumber("closingHeightExtraPercent"),
			closingDurationMs: draftNumber("closingDurationMs"),
			resultsExpandDurationMs: draftNumber("resultsExpandDurationMs"),
			resultsCollapseDurationMs: draftNumber("resultsCollapseDurationMs"),
		});
	};

	return (
		<View className="p-2.5 subBg gap-2 rounded-lg border border-lightBorder dark:border-darkBorder">
			<View>
				<Text className="text-sm text">Search Window Animation</Text>
				<Text className="text-xxs text-neutral-500 dark:text-neutral-400 mt-1">
					Opening uses one controlled rebound and always finishes exactly on
					the final frame. Every window animation value can be tuned here.
				</Text>
			</View>

			<View className="border-t border-lightBorder dark:border-darkBorder" />

			<View>
				<Text className="text-sm text">Opening</Text>
				<Text className="text-xxs text-neutral-500 dark:text-neutral-400 mt-1">
					The window starts larger, contracts slightly past its final size, then
					settles back.
				</Text>
			</View>
			<AnimationNumberRow
				title="Width overshoot"
				description="0–200 pt added to the initial window width"
				value={draft.openingWidthExtra}
				onChangeText={(value) => updateDraft("openingWidthExtra", value)}
				unit="pt"
			/>
			<AnimationNumberRow
				title="Height overshoot"
				description="0–20% added to the initial window height"
				value={draft.openingHeightExtraPercent}
				onChangeText={(value) =>
					updateDraft("openingHeightExtraPercent", value)
				}
				unit="%"
			/>
			<AnimationNumberRow
				title="Duration"
				description="0–1000 ms; 100 ms is the default, 0 disables it"
				value={draft.openingDurationMs}
				onChangeText={(value) => updateDraft("openingDurationMs", value)}
				unit="ms"
			/>
			<AnimationNumberRow
				title="Bounce depth"
				description="0–100% of the initial oversize; 20% gives one restrained rebound"
				value={draft.openingBounce}
				onChangeText={(value) => updateDraft("openingBounce", value)}
				unit="%"
			/>
			<AnimationNumberRow
				title="Initial opacity"
				description="0–100%; controls the opening fade"
				value={draft.openingInitialOpacity}
				onChangeText={(value) => updateDraft("openingInitialOpacity", value)}
				unit="%"
			/>

			<View className="border-t border-lightBorder dark:border-darkBorder" />

			<View>
				<Text className="text-sm text">Results panel</Text>
				<Text className="text-xxs text-neutral-500 dark:text-neutral-400 mt-1">
					Controls how quickly the lower results area unfolds and folds.
				</Text>
			</View>
			<AnimationNumberRow
				title="Expand duration"
				description="0–1000 ms; 0 makes expansion immediate"
				value={draft.resultsExpandDurationMs}
				onChangeText={(value) => updateDraft("resultsExpandDurationMs", value)}
				unit="ms"
			/>
			<AnimationNumberRow
				title="Collapse duration"
				description="0–1000 ms; 0 makes collapse immediate"
				value={draft.resultsCollapseDurationMs}
				onChangeText={(value) =>
					updateDraft("resultsCollapseDurationMs", value)
				}
				unit="ms"
			/>

			<View className="border-t border-lightBorder dark:border-darkBorder" />

			<View>
				<Text className="text-sm text">Closing</Text>
				<Text className="text-xxs text-neutral-500 dark:text-neutral-400 mt-1">
					The window grows slightly while fading out.
				</Text>
			</View>
			<AnimationNumberRow
				title="Width growth"
				description="0–20% added while the window disappears"
				value={draft.closingWidthExtraPercent}
				onChangeText={(value) => updateDraft("closingWidthExtraPercent", value)}
				unit="%"
			/>
			<AnimationNumberRow
				title="Height growth"
				description="0–20% added while the window disappears"
				value={draft.closingHeightExtraPercent}
				onChangeText={(value) =>
					updateDraft("closingHeightExtraPercent", value)
				}
				unit="%"
			/>
			<AnimationNumberRow
				title="Duration"
				description="0–1000 ms; 85 ms keeps closing faster than opening"
				value={draft.closingDurationMs}
				onChangeText={(value) => updateDraft("closingDurationMs", value)}
				unit="ms"
			/>

			{!valuesAreValid && (
				<Text className="text-xs text-red-500">
					Check the ranges shown below each animation setting.
				</Text>
			)}

			<View className="flex-row justify-end gap-2">
				<TouchableOpacity onPress={store.ui.resetSearchWindowAnimation}>
					<View className="px-3 py-1.5 rounded-md border border-color">
						<Text className="text-xs text">Reset</Text>
					</View>
				</TouchableOpacity>
				<TouchableOpacity disabled={!valuesAreValid} onPress={apply}>
					<View
						className={clsx("px-3 py-1.5 rounded-md", {
							"bg-accent-strong": valuesAreValid,
							"bg-neutral-300 dark:bg-neutral-700": !valuesAreValid,
						})}
					>
						<Text className="text-xs text-white">Apply</Text>
					</View>
				</TouchableOpacity>
			</View>

			<Text className="text-xxs text-neutral-500 dark:text-neutral-400">
				Saved as searchWindowAnimation in ~/.config/sol/config.json.
			</Text>
		</View>
	);
});

const SearchWindowPositionSettings = observer(() => {
	const store = useStore();
	const position = store.ui.searchWindowPosition;
	const [x, setX] = useState(String(position.x));
	const [y, setY] = useState(String(position.y));

	useEffect(() => {
		setX(String(position.x));
		setY(String(position.y));
	}, [position.x, position.y]);

	const parsedX = Number(x.replace(",", "."));
	const parsedY = Number(y.replace(",", "."));
	const valuesAreValid =
		x.trim() !== "" &&
		y.trim() !== "" &&
		Number.isFinite(parsedX) &&
		Number.isFinite(parsedY) &&
		parsedX >= 0 &&
		parsedX <= 100 &&
		parsedY >= 0 &&
		parsedY <= 100;

	const reset = () => {
		setX("50");
		setY("20");
		store.ui.resetSearchWindowPosition();
	};

	return (
		<View className="p-2.5 subBg gap-2 rounded-lg border border-lightBorder dark:border-darkBorder">
			<View>
				<Text className="text-sm text">Search Window Position</Text>
				<Text className="text-xxs text-neutral-500 dark:text-neutral-400 mt-1">
					Position the center of the Sol prompt horizontally and its top edge
					vertically.
				</Text>
			</View>

			<View className="border-t border-lightBorder dark:border-darkBorder" />

			<View className="flex-row items-center gap-2">
				<View className="flex-1">
					<Text className="text-sm text">Horizontal (X)</Text>
					<Text className="text-xxs text-neutral-500 dark:text-neutral-400">
						0% left · 50% center · 100% right
					</Text>
				</View>
				<Input
					bordered
					className="w-20 h-7"
					inputClassName="text-right"
					value={x}
					onChangeText={setX}
				/>
				<Text className="text-xs darker-text w-5">%</Text>
			</View>

			<View className="flex-row items-center gap-2">
				<View className="flex-1">
					<Text className="text-sm text">From top (Y)</Text>
					<Text className="text-xxs text-neutral-500 dark:text-neutral-400">
						0% top · 100% bottom
					</Text>
				</View>
				<Input
					bordered
					className="w-20 h-7"
					inputClassName="text-right"
					value={y}
					onChangeText={setY}
				/>
				<Text className="text-xs darker-text w-5">%</Text>
			</View>

			{!valuesAreValid && (
				<Text className="text-xs text-red-500">
					Use values between 0 and 100.
				</Text>
			)}

			<View className="flex-row justify-end gap-2">
				<TouchableOpacity onPress={reset}>
					<View className="px-3 py-1.5 rounded-md border border-color">
						<Text className="text-xs text">Reset</Text>
					</View>
				</TouchableOpacity>
				<TouchableOpacity
					disabled={!valuesAreValid}
					onPress={() => {
						if (!valuesAreValid) return;
						store.ui.setSearchWindowPosition({ x: parsedX, y: parsedY });
					}}
				>
					<View
						className={clsx("px-3 py-1.5 rounded-md", {
							"bg-accent-strong": valuesAreValid,
							"bg-neutral-300 dark:bg-neutral-700": !valuesAreValid,
						})}
					>
						<Text className="text-xs text-white">Apply</Text>
					</View>
				</TouchableOpacity>
			</View>

			<Text className="text-xxs text-neutral-500 dark:text-neutral-400">
				The window always stays fully inside the active screen.
			</Text>
		</View>
	);
});

export const General = observer(() => {
	const store = useStore();
	return (
		<ScrollView
			showsVerticalScrollIndicator={false}
			automaticallyAdjustContentInsets
			className="flex-1"
			contentContainerClassName="p-3 gap-1.5"
		>
			<View className="flex-row items-center p-2.5 subBg rounded-lg border border-lightBorder dark:border-darkBorder">
				<View className="flex-1">
					<Text className="text-sm text">Open at Login</Text>
					<Text className="text-xxs text-neutral-500 dark:text-neutral-400">
						Launch Sol when your computer starts
					</Text>
				</View>
				<MySwitch
					value={store.ui.launchAtLogin}
					onValueChange={store.ui.setLaunchAtLogin}
				/>
			</View>
			<GlassAppearanceSettings />
			<SearchWindowAnimationSettings />
			<SearchWindowPositionSettings />
			<View className="z-20 p-2.5 subBg gap-2 rounded-lg border border-lightBorder dark:border-darkBorder">
				<View className="flex-row items-center z-30">
					<Text className="flex-1 text-sm">Global Shortcut</Text>
					<Dropdown
						className="w-48 h-7"
						value={store.ui.globalShortcut}
						onValueChange={(v) => {
							store.ui.setGlobalShortcut(v as any);
						}}
						options={[
							{ label: "⌘ + ␣", value: "command" as const },
							{ label: "⌥ + ␣", value: "option" as const },
							{ label: "⌃ + ␣", value: "control" as const },
						]}
					/>
				</View>
				<View className="border-t border-lightBorder dark:border-darkBorder" />
				<View className="flex-row items-center z-20">
					<Text className="flex-1 text-sm">Search Engine</Text>
					<Dropdown
						className="w-48 h-7"
						value={store.ui.searchEngine}
						onValueChange={(v) => {
							store.ui.setSearchEngine(v as any);
						}}
						options={[
							{ label: "Google", value: "google" as const },
							{ label: "DuckDuckGo", value: "duckduckgo" as const },
							{ label: "Bing", value: "bing" as const },
							{ label: "Custom", value: "custom" as const },
						]}
					/>
				</View>
				{store.ui.searchEngine === "custom" && (
					<View className="items-end z-10">
						<View className="w-64 flex-row items-center gap-1">
							{store.ui.searchEngine === "custom" &&
								(isValidCustomSearchEngineUrl(store.ui.customSearchUrl) ? (
									<View className="w-2 h-2 rounded-full bg-green-500" />
								) : (
									<View className="w-2 h-2 rounded-full bg-red-500" />
								))}
							<Input
								bordered
								className="w-full h-7 text-xs rounded border border-lightBorder dark:border-darkBorder px-1"
								inputClassName="w-full"
								readOnly={store.ui.searchEngine !== "custom"}
								value={store.ui.customSearchUrl}
								onChangeText={(e) => store.ui.setCustomSearchUrl(e)}
								placeholder="https://google.com/search?q=%s"
							/>
						</View>
						<Text className="text-xs text-neutral-500 dark:text-neutral-400 mt-1 ml-1">
							Use %s in place of the search term
						</Text>
					</View>
				)}
			</View>

			<View className="z-10 p-2.5 gap-1 subBg rounded-lg border border-lightBorder dark:border-darkBorder">
				<Text className="text-sm">File Search Paths</Text>
				<Text className="text-xxs text-neutral-500 dark:text-neutral-400">
					Add folders for the Search Files functionality.
				</Text>
				<View className="mt-2">
					{store.ui.searchFolders.map((folder, idx) => {
						return (
							<View
								key={folder}
								className={clsx("flex-row items-center p-1.5", {
									"rounded-t-lg": idx === 0,
									"rounded-b-lg": idx === store.ui.searchFolders.length - 1,
									"bg-neutral-100 dark:bg-neutral-900": idx % 2 === 0,
									"bg-neutral-200 dark:bg-neutral-800": idx % 2 !== 0,
								})}
							>
								<Text className="flex-1 text-sm">{folder}</Text>
								<TouchableOpacity
									onPress={() => {
										store.ui.removeSearchFolder(folder);
									}}
								>
									<Image
										source={Assets.close}
										className="h-4 w-4"
										style={{ tintColor: "red" }}
									/>
									{/* <Text className="text-red-500">Remove</Text> */}
								</TouchableOpacity>
							</View>
						);
					})}
				</View>
				<View className="justify-end flex-row mt-1.5 gap-3">
					<TouchableOpacity
						onPress={() => {
							store.ui.reindexAll();
						}}
					>
						<Text className="text-sm text-neutral-500">
							{store.ui.isIndexing ? "Indexing..." : "Re-index"}
						</Text>
					</TouchableOpacity>
					<TouchableOpacity
						onPress={async () => {
							try {
								solNative.hideWindow();
								let path = await solNative.openFilePicker();
								if (path) {
									path = path.replace("file://", "");
									path = decodeURI(path);
									store.ui.addSearchFolder(path);
								}
								solNative.showWindow();
							} catch {}
						}}
					>
						<Text className="text-sm text-blue-500">Add folder</Text>
					</TouchableOpacity>
				</View>
			</View>
			<View className="p-2.5 subBg gap-2 rounded-lg border border-lightBorder dark:border-darkBorder">
				<View className="flex-row items-center z-20">
					<Text className="flex-1 text-sm">Show Window on Screen with</Text>
					<Dropdown
						className="w-48 h-7"
						value={store.ui.showWindowOn}
						onValueChange={(v) => {
							store.ui.setShowWindowOn(v as any);
						}}
						options={[
							{
								label: "Frontmost Window",
								value: "screenWithFrontmost" as const,
							},
							{ label: "Cursor Screen", value: "screenWithCursor" as const },
						]}
					/>
				</View>
				<View className="border-t border-lightBorder dark:border-darkBorder z-0" />
				<View className="flex-row items-center">
					<Text className="flex-1 text-sm">Show In-App Calendar</Text>
					<MySwitch
						value={store.ui.calendarEnabled}
						onValueChange={store.ui.setCalendarEnabled}
					/>
				</View>
				<View className="border-t border-lightBorder dark:border-darkBorder" />
				<View className="flex-row items-center">
					<Text className="flex-1 text-sm">Show Browser Bookmarks</Text>
					<MySwitch
						value={store.ui.showInAppBrowserBookMarks}
						onValueChange={store.ui.setShowInAppBrowserBookmarks}
					/>
				</View>
				<View className="border-t border-lightBorder dark:border-darkBorder" />
				<View className="flex-row items-center">
					<Text className="flex-1 text-sm">Show upcoming event in Menu Bar</Text>
					<MySwitch
						value={store.ui.showUpcomingEvent}
						onValueChange={store.ui.setShowUpcomingEvent}
					/>
				</View>
				<View className="border-t border-lightBorder dark:border-darkBorder" />
				<View className="flex-row items-center">
					<Text className="flex-1 text-sm">
						Forward Media Keys to Music Player
					</Text>
					<MySwitch
						value={store.ui.mediaKeyForwardingEnabled}
						onValueChange={() => {
							store.ui.setMediaKeyForwardingEnabled(
								!store.ui.mediaKeyForwardingEnabled,
							);
						}}
					/>
				</View>
			</View>
			<View className="flex-row items-center p-2.5 subBg rounded-lg border border-lightBorder dark:border-darkBorder">
				<View className="flex-1">
					<Text className="text-sm text">Reload Config</Text>
					<Text className="text-xxs text-neutral-500 dark:text-neutral-400">
						Re-read ~/.config/sol/config.json
					</Text>
				</View>
				<TouchableOpacity onPress={() => store.ui.reloadJsonConfig()}>
					<Text className="text-sm text-blue-500">Reload</Text>
				</TouchableOpacity>
			</View>
		</ScrollView>
	);
});
