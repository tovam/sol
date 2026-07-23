import { Dropdown } from "components/Dropdown";
import { languages } from "lib/languages";
import { observer } from "mobx-react-lite";
import { Text, View } from "react-native";
import { useStore } from "store";

export const Translate = observer(() => {
	const store = useStore();

	return (
		<View className="flex-1 p-3">
			<View className="p-2.5 subBg rounded-lg border border-lightBorder dark:border-darkBorder gap-0.5">
				<Text className="text-xxs text">
					Select up to 3 languages for translation
				</Text>
				<View className="flex-row items-center py-1.5 z-20">
					<Text className="flex-1 text-sm">First language</Text>

					<Dropdown
						className="w-36"
						value={store.ui.firstTranslationLanguage}
						onValueChange={(v) =>
							store.ui.setFirstTranslationLanguage(v as string)
						}
						options={Object.values(languages).map((v) => ({
							label: v.name,
							value: v.code,
						}))}
					/>
				</View>
				<View className="flex-row items-center py-1.5 z-10">
					<Text className="flex-1 text-sm">Second language</Text>

					<Dropdown
						className="w-36"
						value={store.ui.secondTranslationLanguage}
						onValueChange={(v) =>
							store.ui.setSecondTranslationLanguage(v as string)
						}
						options={Object.values(languages).map((v, index) => ({
							label: v.name,
							value: v.code,
						}))}
					/>
				</View>
				<View className="flex-row items-center py-1.5">
					<Text className="flex-1 text-sm">Third language</Text>

					<Dropdown
						className="w-36"
						value={store.ui.thirdTranslationLanguage ?? ""}
						onValueChange={(v) =>
							store.ui.setThirdTranslationLanguage(v as string)
						}
						options={Object.values(languages).map((v) => ({
							label: v.name,
							value: v.code,
						}))}
					/>
				</View>
			</View>
		</View>
	);
});
