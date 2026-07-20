import { BackButton } from "components/BackButton";
import { TextInput } from "components/TextInput";
import { solNative } from "lib/SolNative";
import { type FC, useEffect, useMemo, useState } from "react";
import { Clipboard, Text, TouchableOpacity, View } from "react-native";
import { useStore } from "store";
import { Widget } from "stores/ui.store";

type RGB = { red: number; green: number; blue: number };
type HSL = { hue: number; saturation: number; lightness: number };

const HUE_STOPS = Array.from({ length: 24 }, (_, index) => index * 15);
const SATURATION_STEPS = [0, 20, 40, 60, 80, 100];
const LIGHTNESS_STEPS = [20, 32, 44, 56, 68, 80];

function componentToHex(component: number) {
	return Math.round(component).toString(16).padStart(2, "0").toUpperCase();
}

function rgbToHex({ red, green, blue }: RGB) {
	return `#${componentToHex(red)}${componentToHex(green)}${componentToHex(blue)}`;
}

function hslToRgb({ hue, saturation, lightness }: HSL): RGB {
	const normalizedSaturation = saturation / 100;
	const normalizedLightness = lightness / 100;
	const chroma =
		(1 - Math.abs(2 * normalizedLightness - 1)) * normalizedSaturation;
	const hueSegment = (((hue % 360) + 360) % 360) / 60;
	const intermediate = chroma * (1 - Math.abs((hueSegment % 2) - 1));
	let red = 0;
	let green = 0;
	let blue = 0;

	if (hueSegment < 1) {
		red = chroma;
		green = intermediate;
	} else if (hueSegment < 2) {
		red = intermediate;
		green = chroma;
	} else if (hueSegment < 3) {
		green = chroma;
		blue = intermediate;
	} else if (hueSegment < 4) {
		green = intermediate;
		blue = chroma;
	} else if (hueSegment < 5) {
		red = intermediate;
		blue = chroma;
	} else {
		red = chroma;
		blue = intermediate;
	}

	const adjustment = normalizedLightness - chroma / 2;
	return {
		red: (red + adjustment) * 255,
		green: (green + adjustment) * 255,
		blue: (blue + adjustment) * 255,
	};
}

function rgbToHsl({ red, green, blue }: RGB): HSL {
	const normalizedRed = red / 255;
	const normalizedGreen = green / 255;
	const normalizedBlue = blue / 255;
	const maximum = Math.max(normalizedRed, normalizedGreen, normalizedBlue);
	const minimum = Math.min(normalizedRed, normalizedGreen, normalizedBlue);
	const delta = maximum - minimum;
	let hue = 0;

	if (delta !== 0) {
		if (maximum === normalizedRed) {
			hue = 60 * (((normalizedGreen - normalizedBlue) / delta) % 6);
		} else if (maximum === normalizedGreen) {
			hue = 60 * ((normalizedBlue - normalizedRed) / delta + 2);
		} else {
			hue = 60 * ((normalizedRed - normalizedGreen) / delta + 4);
		}
	}

	const lightness = (maximum + minimum) / 2;
	const saturation =
		delta === 0 ? 0 : delta / (1 - Math.abs(2 * lightness - 1));
	return {
		hue: Math.round((hue + 360) % 360),
		saturation: Math.round(saturation * 100),
		lightness: Math.round(lightness * 100),
	};
}

function parseHex(input: string): RGB | null {
	const normalized = input.trim().replace(/^#/, "");
	const expanded =
		normalized.length === 3
			? normalized
					.split("")
					.map((character) => character.repeat(2))
					.join("")
			: normalized;
	if (!/^[0-9a-fA-F]{6}$/.test(expanded)) {
		return null;
	}

	return {
		red: Number.parseInt(expanded.slice(0, 2), 16),
		green: Number.parseInt(expanded.slice(2, 4), 16),
		blue: Number.parseInt(expanded.slice(4, 6), 16),
	};
}

export const ColorPickerWidget: FC = () => {
	const store = useStore();
	const [hue, setHue] = useState(210);
	const [saturation, setSaturation] = useState(80);
	const [lightness, setLightness] = useState(56);
	const rgb = useMemo(
		() => hslToRgb({ hue, saturation, lightness }),
		[hue, saturation, lightness],
	);
	const hex = useMemo(() => rgbToHex(rgb), [rgb]);
	const [hexInput, setHexInput] = useState(hex);

	useEffect(() => {
		setHexInput(hex);
	}, [hex]);

	const copyValue = (value: string) => {
		Clipboard.setString(value);
		void solNative.showToast(`Copied ${value}`, "success");
	};

	const applyHexInput = () => {
		const parsed = parseHex(hexInput);
		if (!parsed) {
			void solNative.showToast("Invalid HEX color", "error");
			return;
		}
		const next = rgbToHsl(parsed);
		setHue(next.hue);
		setSaturation(next.saturation);
		setLightness(next.lightness);
	};

	const roundedRgb = {
		red: Math.round(rgb.red),
		green: Math.round(rgb.green),
		blue: Math.round(rgb.blue),
	};
	const rgbValue = `rgb(${roundedRgb.red}, ${roundedRgb.green}, ${roundedRgb.blue})`;
	const hslValue = `hsl(${hue}, ${saturation}%, ${lightness}%)`;

	return (
		<View className="fullWindow">
			<View className="h-16 px-5 flex-row items-center gap-3 border-b border-color">
				<BackButton
					onPress={() => {
						store.ui.setQuery("");
						store.ui.focusWidget(Widget.SEARCH);
					}}
				/>
				<View className="flex-1">
					<Text className="text-xl font-semibold text">Color Picker</Text>
					<Text className="text-xs darker-text">
						Choose a color, then click a value to copy it
					</Text>
				</View>
			</View>

			<View className="flex-1 flex-row gap-6 p-6">
				<View className="flex-1 gap-4">
					<View className="h-60 rounded-xl overflow-hidden border border-color">
						{LIGHTNESS_STEPS.map((nextLightness) => (
							<View key={nextLightness} className="flex-1 flex-row">
								{SATURATION_STEPS.map((nextSaturation) => {
									const cellColor = rgbToHex(
										hslToRgb({
											hue,
											saturation: nextSaturation,
											lightness: nextLightness,
										}),
									);
									const selected =
										nextSaturation === saturation &&
										nextLightness === lightness;
									return (
										<TouchableOpacity
											key={nextSaturation}
											className="flex-1"
											style={{
												backgroundColor: cellColor,
												borderWidth: selected ? 3 : 0,
												borderColor: selected ? "white" : "transparent",
											}}
											onPress={() => {
												setSaturation(nextSaturation);
												setLightness(nextLightness);
											}}
										/>
									);
								})}
							</View>
						))}
					</View>

					<View className="flex-row h-7 rounded-lg overflow-hidden border border-color">
						{HUE_STOPS.map((nextHue) => (
							<TouchableOpacity
								key={nextHue}
								className="flex-1"
								style={{
									backgroundColor: rgbToHex(
										hslToRgb({
											hue: nextHue,
											saturation: 100,
											lightness: 50,
										}),
									),
									borderTopWidth: Math.abs(nextHue - hue) < 8 ? 4 : 0,
									borderTopColor: "white",
								}}
								onPress={() => setHue(nextHue)}
							/>
						))}
					</View>
				</View>

				<View className="w-64 gap-3">
					<View
						className="h-28 rounded-xl border border-color items-center justify-center"
						style={{ backgroundColor: hex }}
					>
						<Text
							className="text-xl font-semibold"
							style={{ color: lightness > 62 ? "black" : "white" }}
						>
							{hex}
						</Text>
					</View>

					<View className="h-10 rounded-lg px-3 flex-row items-center border border-color subBg">
						<TextInput
							className="flex-1 text-base font-mono text"
							enableFocusRing={false}
							value={hexInput}
							onChangeText={setHexInput}
							onSubmitEditing={applyHexInput}
						/>
						<TouchableOpacity onPress={applyHexInput}>
							<Text className="text-sm text-accent-strong">Apply</Text>
						</TouchableOpacity>
					</View>

					{[
						["HEX", hex],
						["RGB", rgbValue],
						["HSL", hslValue],
					].map(([label, value]) => (
						<TouchableOpacity
							key={label}
							className="rounded-lg p-3 subBg border border-color"
							onPress={() => copyValue(value)}
						>
							<Text className="text-xxs uppercase darker-text">{label}</Text>
							<Text className="text-sm font-mono text" numberOfLines={1}>
								{value}
							</Text>
						</TouchableOpacity>
					))}
				</View>
			</View>
		</View>
	);
};
