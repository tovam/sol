import "react-native-get-random-values";
import { BackButton } from "components/BackButton";
import { solNative } from "lib/SolNative";
import { type FC, useMemo, useState } from "react";
import { Clipboard, Text, TouchableOpacity, View } from "react-native";
import { useStore } from "store";
import { Widget } from "stores/ui.store";

type PasswordOptions = {
	lowercase: boolean;
	uppercase: boolean;
	numbers: boolean;
	symbols: boolean;
};

const CHARACTER_SETS = {
	lowercase: "abcdefghijkmnopqrstuvwxyz",
	uppercase: "ABCDEFGHJKLMNPQRSTUVWXYZ",
	numbers: "23456789",
	symbols: "!@#$%^&*()-_=+[]{};:,.?",
};

function secureRandomIndex(maximum: number) {
	const limit = Math.floor(0x1_0000_0000 / maximum) * maximum;
	const random = new Uint32Array(1);
	do {
		globalThis.crypto.getRandomValues(random);
	} while (random[0] >= limit);
	return random[0] % maximum;
}

export function generatePassword(length: number, options: PasswordOptions) {
	const enabledSets = Object.entries(CHARACTER_SETS)
		.filter(([key]) => options[key as keyof PasswordOptions])
		.map(([, characters]) => characters);
	if (enabledSets.length === 0) return "";

	const safeLength = Math.max(enabledSets.length, Math.min(128, length));
	const allCharacters = enabledSets.join("");
	const password = enabledSets.map(
		(characters) => characters[secureRandomIndex(characters.length)],
	);
	while (password.length < safeLength) {
		password.push(allCharacters[secureRandomIndex(allCharacters.length)]);
	}

	for (let index = password.length - 1; index > 0; index -= 1) {
		const swapIndex = secureRandomIndex(index + 1);
		[password[index], password[swapIndex]] = [
			password[swapIndex],
			password[index],
		];
	}
	return password.join("");
}

export const PasswordGeneratorWidget: FC = () => {
	const store = useStore();
	const [length, setLength] = useState(20);
	const [options, setOptions] = useState<PasswordOptions>({
		lowercase: true,
		uppercase: true,
		numbers: true,
		symbols: true,
	});
	const [generation, setGeneration] = useState(0);
	const password = useMemo(() => {
		void generation;
		return generatePassword(length, options);
	}, [length, options, generation]);

	const toggle = (key: keyof PasswordOptions) => {
		const enabledCount = Object.values(options).filter(Boolean).length;
		if (options[key] && enabledCount === 1) return;
		setOptions({ ...options, [key]: !options[key] });
	};

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
					<Text className="text-xl font-semibold text">Password Generator</Text>
					<Text className="text-xs darker-text">
						Cryptographically secure · ambiguous characters removed
					</Text>
				</View>
			</View>

			<View className="flex-1 px-10 py-7 gap-5">
				<View className="min-h-24 rounded-2xl subBg border border-color px-6 py-5 items-center justify-center">
					<Text className="text-2xl font-mono text text-center" selectable>
						{password}
					</Text>
				</View>

				<View className="flex-row items-center justify-between">
					<Text className="text-base font-semibold text">Length</Text>
					<View className="flex-row gap-2">
						{[12, 16, 20, 32, 48].map((nextLength) => (
							<TouchableOpacity
								key={nextLength}
								className={`w-12 py-2 rounded-lg items-center border ${
									length === nextLength
										? "bg-accent-strong border-transparent"
										: "subBg border-color"
								}`}
								onPress={() => setLength(nextLength)}
							>
								<Text className={length === nextLength ? "text-white" : "text"}>
									{nextLength}
								</Text>
							</TouchableOpacity>
						))}
					</View>
				</View>

				<View className="flex-row gap-3">
					{(
						[
							["lowercase", "a–z"],
							["uppercase", "A–Z"],
							["numbers", "2–9"],
							["symbols", "!@#"],
						] as const
					).map(([key, label]) => (
						<TouchableOpacity
							key={key}
							className={`flex-1 py-4 rounded-xl border items-center ${
								options[key]
									? "bg-accent-strong border-transparent"
									: "subBg border-color"
							}`}
							onPress={() => toggle(key)}
						>
							<Text
								className={options[key] ? "text-white font-semibold" : "text"}
							>
								{label}
							</Text>
						</TouchableOpacity>
					))}
				</View>

				<View className="flex-row gap-3 mt-auto">
					<TouchableOpacity
						className="flex-1 py-3 rounded-xl subBg border border-color items-center"
						onPress={() => setGeneration((value) => value + 1)}
					>
						<Text className="text font-semibold">Regenerate</Text>
					</TouchableOpacity>
					<TouchableOpacity
						className="flex-1 py-3 rounded-xl bg-accent-strong items-center"
						onPress={() => {
							Clipboard.setString(password);
							void solNative.showToast("Password copied", "success");
						}}
					>
						<Text className="text-white font-semibold">Copy password</Text>
					</TouchableOpacity>
				</View>
			</View>
		</View>
	);
};
