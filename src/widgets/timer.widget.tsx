import { BackButton } from "components/BackButton";
import { TextInput } from "components/TextInput";
import { observer } from "mobx-react-lite";
import { type FC, useEffect, useState } from "react";
import { Text, TouchableOpacity, View } from "react-native";
import { useStore } from "store";
import { formatTimerDuration, parseTimerDuration } from "stores/timer.store";
import { Widget } from "stores/ui.store";

const PRESETS = [60, 300, 600, 1_500];

export const TimerWidget: FC = observer(() => {
	const store = useStore();
	const timer = store.timer;
	const [durationInput, setDurationInput] = useState("5m");
	const [inputError, setInputError] = useState("");

	useEffect(() => {
		if (timer.status === "finished") setDurationInput("5m");
	}, [timer.status]);

	const startFromInput = () => {
		const seconds = parseTimerDuration(durationInput);
		if (seconds == null) {
			setInputError("Try 90s, 5m, or 1h 30m");
			return;
		}
		setInputError("");
		timer.start(seconds);
	};

	const isActive = timer.status === "running" || timer.status === "paused";

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
					<Text className="text-xl font-semibold text">Timer</Text>
					<Text className="text-xs darker-text">
						It keeps running when Sol is hidden
					</Text>
				</View>
			</View>

			<View className="flex-1 items-center justify-center gap-5 px-10">
				<Text className="text-6xl font-light tabular-nums text">
					{formatTimerDuration(timer.remainingSeconds)}
				</Text>
				<Text className="text-sm darker-text uppercase">{timer.status}</Text>

				{!isActive && (
					<>
						<View className="w-80 h-11 rounded-xl px-4 border border-color subBg justify-center">
							<TextInput
								autoFocus
								enableFocusRing={false}
								className="text-lg text text-center"
								value={durationInput}
								onChangeText={setDurationInput}
								onSubmitEditing={startFromInput}
								placeholder="5m"
							/>
						</View>
						{!!inputError && (
							<Text className="text-sm text-red-500">{inputError}</Text>
						)}
						<View className="flex-row gap-2">
							{PRESETS.map((seconds) => (
								<TouchableOpacity
									key={seconds}
									className="px-4 py-2 rounded-lg subBg border border-color"
									onPress={() => {
										setDurationInput(`${seconds / 60}m`);
										timer.start(seconds);
									}}
								>
									<Text className="text">{seconds / 60}m</Text>
								</TouchableOpacity>
							))}
						</View>
						<TouchableOpacity
							className="w-44 py-3 rounded-xl bg-accent-strong items-center"
							onPress={startFromInput}
						>
							<Text className="text-white font-semibold">Start timer</Text>
						</TouchableOpacity>
					</>
				)}

				{isActive && (
					<View className="flex-row gap-3">
						<TouchableOpacity
							className="w-36 py-3 rounded-xl bg-accent-strong items-center"
							onPress={timer.status === "running" ? timer.pause : timer.resume}
						>
							<Text className="text-white font-semibold">
								{timer.status === "running" ? "Pause" : "Resume"}
							</Text>
						</TouchableOpacity>
						<TouchableOpacity
							className="w-36 py-3 rounded-xl subBg border border-color items-center"
							onPress={timer.cancel}
						>
							<Text className="text font-semibold">Cancel</Text>
						</TouchableOpacity>
					</View>
				)}
			</View>
		</View>
	);
});
