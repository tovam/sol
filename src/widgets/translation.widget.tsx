import clsx from "clsx";
import { MainInput } from "components/MainInput";
import { languages } from "lib/languages";
import { solNative } from "lib/SolNative";
import { getTranslationDisplay } from "lib/translator";
import { observer } from "mobx-react-lite";
import { type FC, useEffect } from "react";
import {
	ActivityIndicator,
	Clipboard,
	ScrollView,
	type StyleProp,
	Text,
	TouchableOpacity,
	View,
	type ViewStyle,
} from "react-native";
import { useStore } from "store";

interface Props {
	style?: StyleProp<ViewStyle>;
	className?: string;
}

type TranslationCardProps = {
	languageCode: string;
	primary: string;
	secondary: string | null;
	selected: boolean;
	onCopy: () => void;
	onSelect: () => void;
};

function getLanguageName(languageCode: string) {
	return (
		Object.values(languages).find(({ code }) => code === languageCode)?.name ??
		languageCode.toUpperCase()
	);
}

const TranslationCard: FC<TranslationCardProps> = ({
	languageCode,
	primary,
	secondary,
	selected,
	onCopy,
	onSelect,
}) => (
	<TouchableOpacity
		className={clsx(
			"flex-1 rounded-2xl border overflow-hidden",
			selected ? "border-accent-strong bg-accent-dark" : "border-color subBg",
		)}
		onPress={onSelect}
	>
		<View className="h-12 px-4 flex-row items-center border-b border-color">
			<View className="flex-1 flex-row items-center gap-2">
				<Text className="text-sm font-semibold text">
					{getLanguageName(languageCode)}
				</Text>
				<Text className="text-xs darker-text uppercase">{languageCode}</Text>
			</View>
			{!!secondary && (
				<View className="px-2 py-1 rounded-md bg-accent-dark mr-2">
					<Text className="text-xxs text-accent">LATIN + ЋИРИЛИЦА</Text>
				</View>
			)}
			<TouchableOpacity
				className="px-3 py-1 rounded-lg border border-color"
				onPress={onCopy}
			>
				<Text className="text-xs text">Copy</Text>
			</TouchableOpacity>
		</View>

		<ScrollView
			className="flex-1"
			contentContainerStyle={{ padding: 16 }}
			showsVerticalScrollIndicator
		>
			{!!secondary && (
				<Text className="text-xxs font-semibold darker-text mb-2">LATIN</Text>
			)}
			<Text selectable className="text-lg text leading-7">
				{primary || "No translation returned"}
			</Text>

			{!!secondary && (
				<View className="mt-5 pt-4 border-t border-color">
					<Text className="text-xxs font-semibold darker-text mb-2">
						ЋИРИЛИЦА
					</Text>
					<Text selectable className="text-base darker-text leading-6">
						{secondary}
					</Text>
				</View>
			)}
		</ScrollView>

		{selected && (
			<View className="absolute left-0 top-3 bottom-3 w-1 bg-accent-strong rounded-full" />
		)}
	</TouchableOpacity>
);

export const TranslationWidget: FC<Props> = observer(({ style, className }) => {
	const store = useStore();

	useEffect(() => {
		solNative.turnOnHorizontalArrowsListeners();

		return () => {
			solNative.turnOffHorizontalArrowsListeners();
		};
	}, []);

	const translationLanguages = [
		store.ui.firstTranslationLanguage,
		store.ui.secondTranslationLanguage,
		store.ui.thirdTranslationLanguage,
	].filter((language): language is string => Boolean(language));
	const cards = translationLanguages.map((languageCode, index) => ({
		index,
		languageCode,
		...getTranslationDisplay(
			store.ui.translationResults[index] ?? "",
			languageCode,
		),
	}));
	const hasTranslations = cards.some(({ primary }) => Boolean(primary));

	return (
		<View className={`flex-1 ${className ?? ""}`} style={style}>
			<View className="flex-row px-3 border-b border-color">
				<MainInput placeholder="Translate…" showBackButton />
			</View>

			{store.ui.isLoading && (
				<View className="flex-1 items-center justify-center gap-3">
					<ActivityIndicator />
					<Text className="text-sm darker-text">Translating…</Text>
				</View>
			)}

			{!store.ui.isLoading && !hasTranslations && (
				<View className="flex-1 items-center justify-center gap-2">
					<Text className="text-lg font-semibold text">No translation</Text>
					<Text className="text-sm darker-text">
						Try again or check your connection.
					</Text>
				</View>
			)}

			{!store.ui.isLoading && hasTranslations && (
				<View className="flex-1 flex-row gap-3 p-4">
					{cards.map((card) => (
						<TranslationCard
							key={`${card.languageCode}-${card.index}`}
							languageCode={card.languageCode}
							primary={card.primary}
							secondary={card.secondary}
							selected={store.ui.selectedIndex === card.index}
							onSelect={() => store.ui.setSelectedIndex(card.index)}
							onCopy={() => {
								Clipboard.setString(card.primary);
								void solNative.showToast(
									`${getLanguageName(card.languageCode)} copied`,
									"success",
								);
							}}
						/>
					))}
				</View>
			)}

			<View className="h-9 px-4 flex-row items-center justify-end gap-2 subBg border-t border-color">
				<Text className="text-xs darker-text">← → Select</Text>
				<View className="w-px h-4 bg-neutral-400/30" />
				<Text className="text-xs darker-text">↵ Copy</Text>
			</View>
		</View>
	);
});
