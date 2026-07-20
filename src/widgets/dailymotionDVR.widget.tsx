import { Dropdown } from "components/Dropdown";
import { TextInput } from "components/TextInput";
import { extractDailymotionVideoID } from "lib/dailymotion";
import {
	type DailymotionDVRInspection,
	type DailymotionDVRRecordingState,
	solNative,
} from "lib/SolNative";
import { observer } from "mobx-react-lite";
import prettyBytes from "pretty-bytes";
import { type FC, useEffect, useMemo, useRef, useState } from "react";
import { ScrollView, Text, TouchableOpacity, View } from "react-native";
import { useStore } from "store";

const CUSTOM_SOURCE = "__custom__";
const SAFETY_MARGIN_BYTES = 256 * 1024 * 1024;
const DEFAULT_DESTINATION = `/Users/${solNative.userName()}/Movies`;

type BoundaryMode = "edge" | "clock";
type InspectionStatus = "idle" | "inspecting" | "ready" | "error";

function pickedDirectoryPath(value: string) {
	if (!value.startsWith("file://")) return value;
	try {
		return decodeURIComponent(new URL(value).pathname);
	} catch {
		return value.replace(/^file:\/\//, "");
	}
}

function formatClock(date: Date) {
	return [date.getHours(), date.getMinutes(), date.getSeconds()]
		.map((part) => part.toString().padStart(2, "0"))
		.join(":");
}

function formatDetailedClock(date: Date) {
	return new Intl.DateTimeFormat(undefined, {
		weekday: "short",
		day: "2-digit",
		month: "short",
		hour: "2-digit",
		minute: "2-digit",
		second: "2-digit",
	}).format(date);
}

function formatDuration(seconds: number) {
	const total = Math.max(0, Math.round(seconds));
	const hours = Math.floor(total / 3600);
	const minutes = Math.floor((total % 3600) / 60);
	const remaining = total % 60;
	return [hours, minutes, remaining]
		.map((part) => part.toString().padStart(2, "0"))
		.join(":");
}

function parseClockInRange(value: string, rangeStart: Date, rangeEnd: Date) {
	const match = value.trim().match(/^([01]\d|2[0-3]):([0-5]\d)(?::([0-5]\d))?$/);
	if (!match) return null;
	const hour = Number(match[1]);
	const minute = Number(match[2]);
	const second = Number(match[3] ?? 0);
	const candidates = [-1, 0, 1, 2]
		.map(
			(dayOffset) =>
				new Date(
					rangeStart.getFullYear(),
					rangeStart.getMonth(),
					rangeStart.getDate() + dayOffset,
					hour,
					minute,
					second,
				),
		)
		.filter(
			(candidate) =>
				candidate.getTime() >= rangeStart.getTime() - 500 &&
				candidate.getTime() <= rangeEnd.getTime() + 500,
		);
	return candidates[0] ?? null;
}

function safeFilename(value: string) {
	const cleaned = value
		.replace(/[/:\0]/g, "-")
		.replace(/\s+/g, " ")
		.trim();
	if (!cleaned) return "Dailymotion DVR.mp4";
	return cleaned.toLowerCase().endsWith(".mp4") ? cleaned : `${cleaned}.mp4`;
}

function defaultFilename(title: string, start: Date, end: Date) {
	const range = `${formatClock(start).replace(/:/g, "-")}–${formatClock(end).replace(/:/g, "-")}`;
	return safeFilename(`${title} — ${range}`);
}

function bitrateFallback(height: number | null) {
	if (height != null && height <= 360) return 900;
	if (height != null && height <= 480) return 1500;
	if (height != null && height <= 720) return 3500;
	if (height == null || height <= 1080) return 6500;
	return 12000;
}

function isActiveRecording(state: DailymotionDVRRecordingState) {
	return ["preparing", "recording", "finalizing", "cancelling"].includes(
		state.status,
	);
}

function resolveSelection(
	inspection: DailymotionDVRInspection | undefined,
	startMode: BoundaryMode,
	startClock: string,
	endMode: BoundaryMode,
	endClock: string,
) {
	if (!inspection) return { start: null, end: null, error: "" };
	const rangeStart = new Date(inspection.start);
	const rangeEnd = new Date(inspection.end);
	const start =
		startMode === "edge"
			? rangeStart
			: parseClockInRange(startClock, rangeStart, rangeEnd);
	const end =
		endMode === "edge"
			? rangeEnd
			: parseClockInRange(endClock, rangeStart, rangeEnd);
	if (!start) return { start, end, error: "Start must be a time inside the DVR." };
	if (!end) return { start, end, error: "End must be a time inside the DVR." };
	if (end <= start) return { start, end, error: "End must be after start." };
	return { start, end, error: "" };
}

type BoundaryRowProps = {
	label: string;
	edgeLabel: string;
	mode: BoundaryMode;
	clock: string;
	disabled: boolean;
	onModeChange: (mode: BoundaryMode) => void;
	onClockChange: (value: string) => void;
};

const BoundaryRow: FC<BoundaryRowProps> = ({
	label,
	edgeLabel,
	mode,
	clock,
	disabled,
	onModeChange,
	onClockChange,
}) => (
	<View className="gap-2 py-2 border-b border-color">
		<View className="flex-row items-center gap-2">
			<Text className="flex-1 text-xs font-semibold darker-text">{label}</Text>
			<TouchableOpacity
				disabled={disabled}
				className={`px-3 py-1.5 rounded-md border ${
					mode === "edge" ? "border-accent-strong" : "border-color"
				}`}
				onPress={() => onModeChange("edge")}
			>
				<Text className={mode === "edge" ? "text-accent font-medium" : "text"}>
					{edgeLabel}
				</Text>
			</TouchableOpacity>
			<TouchableOpacity
				disabled={disabled}
				className={`px-3 py-1.5 rounded-md border ${
					mode === "clock" ? "border-accent-strong" : "border-color"
				}`}
				onPress={() => onModeChange("clock")}
			>
				<Text className={mode === "clock" ? "text-accent font-medium" : "text"}>
					At time
				</Text>
			</TouchableOpacity>
		</View>
		{mode === "clock" && (
			<View className="w-full px-3 py-1.5 border-b border-accent-strong">
				<TextInput
					enableFocusRing={false}
					editable={!disabled}
					className="text text-base"
					value={clock}
					onChangeText={onClockChange}
					placeholder="HH:mm:ss"
				/>
			</View>
		)}
	</View>
);

export const DailymotionDVRWidget: FC = observer(() => {
	const store = useStore();
	const streams = store.ui.dailymotionStreams;
	const [sourceID, setSourceID] = useState(streams[0]?.id ?? CUSTOM_SOURCE);
	const [customURL, setCustomURL] = useState("");
	const [qualityHeight, setQualityHeight] = useState<number | null>(null);
	const [inspectionStatus, setInspectionStatus] =
		useState<InspectionStatus>("idle");
	const [inspection, setInspection] = useState<DailymotionDVRInspection>();
	const [inspectionError, setInspectionError] = useState("");
	const [startMode, setStartMode] = useState<BoundaryMode>("edge");
	const [endMode, setEndMode] = useState<BoundaryMode>("edge");
	const [startClock, setStartClock] = useState("");
	const [endClock, setEndClock] = useState("");
	const [destination, setDestination] = useState(DEFAULT_DESTINATION);
	const [destinationCapacity, setDestinationCapacity] = useState<number | null>(null);
	const [destinationCapacityError, setDestinationCapacityError] = useState(false);
	const [filename, setFilename] = useState("Dailymotion DVR.mp4");
	const [filenameEdited, setFilenameEdited] = useState(false);
	const [recording, setRecording] = useState<DailymotionDVRRecordingState>({
		status: "idle",
	});
	const [formError, setFormError] = useState("");
	const [isStarting, setIsStarting] = useState(false);
	const inspectionSequence = useRef(0);
	const startInFlight = useRef(false);

	const selectedStream = streams.find((stream) => stream.id === sourceID);
	const sourceURL =
		sourceID === CUSTOM_SOURCE ? customURL.trim() : selectedStream?.url ?? "";
	const sourceIsValid = Boolean(extractDailymotionVideoID(sourceURL));
	const active = isActiveRecording(recording);
	const controlsDisabled = active || isStarting;

	useEffect(() => {
		if (sourceID !== CUSTOM_SOURCE && !selectedStream) {
			setSourceID(streams[0]?.id ?? CUSTOM_SOURCE);
		}
	}, [selectedStream, sourceID, streams]);

	useEffect(() => {
		let mounted = true;
		let receivedEvent = false;
		const subscription = solNative.addListener(
			"dailymotionDVRRecordingChanged",
			(state: DailymotionDVRRecordingState) => {
				receivedEvent = true;
				setRecording(state);
			},
		);
		void solNative.getDailymotionDVRRecordingState().then((state) => {
			if (mounted && !receivedEvent) setRecording(state);
		});
		return () => {
			mounted = false;
			subscription.remove();
		};
	}, []);

	useEffect(() => {
		let mounted = true;
		setDestinationCapacity(null);
		setDestinationCapacityError(false);
		void solNative
			.getDailymotionDVRDestinationCapacity(destination)
			.then((capacity) => {
				if (!mounted) return;
				if (capacity > 0) {
					setDestinationCapacity(capacity);
				} else {
					setDestinationCapacityError(true);
				}
			})
			.catch(() => {
				if (mounted) setDestinationCapacityError(true);
			});
		return () => {
			mounted = false;
		};
	}, [destination]);

	useEffect(() => {
		const sequence = ++inspectionSequence.current;
		setInspection(undefined);
		setInspectionError("");
		if (!sourceIsValid || active) {
			setInspectionStatus("idle");
			return;
		}

		setInspectionStatus("inspecting");
		const timer = setTimeout(() => {
			void solNative
				.inspectDailymotionDVR(sourceURL, qualityHeight)
				.then((nextInspection) => {
					if (inspectionSequence.current !== sequence) return;
					setInspection(nextInspection);
					setInspectionStatus("ready");
					setStartClock(formatClock(new Date(nextInspection.start)));
					setEndClock(formatClock(new Date(nextInspection.end)));
					if (
						qualityHeight != null &&
						!nextInspection.qualities.some(
							(quality) => quality.height === qualityHeight,
						)
					) {
						setQualityHeight(null);
					}
				})
				.catch((error) => {
					if (inspectionSequence.current !== sequence) return;
					setInspectionStatus("error");
					setInspectionError(
						error instanceof Error ? error.message : "Could not inspect this DVR.",
					);
				});
		}, 250);
		return () => {
			clearTimeout(timer);
			if (inspectionSequence.current === sequence) {
				inspectionSequence.current += 1;
			}
		};
	}, [active, qualityHeight, sourceIsValid, sourceURL]);

	const selection = useMemo(
		() =>
			resolveSelection(
				inspection,
				startMode,
				startClock,
				endMode,
				endClock,
			),
		[endClock, endMode, inspection, startClock, startMode],
	);

	useEffect(() => {
		if (!inspection || !selection.start || !selection.end || filenameEdited) return;
		setFilename(defaultFilename(inspection.title, selection.start, selection.end));
	}, [filenameEdited, inspection, selection.end, selection.start]);

	const selectedDuration =
		selection.start && selection.end
			? (selection.end.getTime() - selection.start.getTime()) / 1000
			: 0;
	const inferredHeight = qualityHeight ?? inspection?.qualities[0]?.height ?? null;
	const inspectedBitrate = inspection?.bitrateKbps ?? 0;
	const bitrate =
		inspectedBitrate > 0 ? inspectedBitrate : bitrateFallback(inferredHeight);
	const estimatedBytes = selectedDuration * ((bitrate * 1000) / 8) * 1.15;
	const availableBytes = destinationCapacity ?? 0;
	const lacksDiskSpace =
		availableBytes > 0 && estimatedBytes + SAFETY_MARGIN_BYTES > availableBytes;
	const rangeStart = inspection ? new Date(inspection.start) : null;
	const rangeEnd = inspection ? new Date(inspection.end) : null;
	const selectionStartPercent =
		rangeStart && rangeEnd && selection.start
			? ((selection.start.getTime() - rangeStart.getTime()) /
					(rangeEnd.getTime() - rangeStart.getTime())) *
				100
			: 0;
	const selectionEndPercent =
		rangeStart && rangeEnd && selection.end
			? ((selection.end.getTime() - rangeStart.getTime()) /
					(rangeEnd.getTime() - rangeStart.getTime())) *
				100
			: 100;
	const outputPath = `${destination.replace(/\/$/, "")}/${safeFilename(filename)}`;
	const canRecord = Boolean(
		inspection?.isDVR &&
		selection.start &&
		selection.end &&
		!selection.error &&
		!lacksDiskSpace &&
		destinationCapacity != null &&
		!active &&
		!isStarting,
	);

	const sourceOptions = [
		...streams.map((stream) => ({ label: stream.name, value: stream.id })),
		{ label: "Another Dailymotion URL…", value: CUSTOM_SOURCE },
	];
	const qualityOptions = [
		{ label: "Auto (best available)", value: "auto" },
		...(inspection?.qualities ?? []).map((quality) => ({
			label: quality.label,
			value: String(quality.height),
		})),
	];

	const pickDestination = async () => {
		try {
			const picked = await solNative.openFilePicker();
			if (picked) setDestination(pickedDirectoryPath(picked));
		} catch {
			// Cancelling the native picker is expected.
		}
	};

	const startRecording = async () => {
		if (
			startInFlight.current ||
			!canRecord ||
			!selection.start ||
			!selection.end
		)
			return;
		startInFlight.current = true;
		setIsStarting(true);
		setFormError("");
		try {
			const freshInspection = await solNative.inspectDailymotionDVR(
				sourceURL,
				qualityHeight,
			);
			if (!freshInspection.isDVR) {
				throw new Error("This stream no longer exposes a live DVR window.");
			}
			const freshSelection = resolveSelection(
				freshInspection,
				startMode,
				startClock,
				endMode,
				endClock,
			);
			setInspection(freshInspection);
			if (!freshSelection.start || !freshSelection.end || freshSelection.error) {
				throw new Error(freshSelection.error || "The selected range is no longer available.");
			}
			const state = await solNative.startDailymotionDVRRecording({
				url: sourceURL,
				qualityHeight,
				start: freshSelection.start.toISOString(),
				end: freshSelection.end.toISOString(),
				startAtDVRBeginning: startMode === "edge",
				endAtDVREnd: endMode === "edge",
				outputPath,
			});
			setRecording(state);
		} catch (error) {
			setFormError(
				error instanceof Error ? error.message : "Could not start the recording.",
				);
		} finally {
			startInFlight.current = false;
			setIsStarting(false);
		}
	};

	const cancelRecording = async () => {
		if (!recording.id) return;
		try {
			await solNative.cancelDailymotionDVRRecording(recording.id);
		} catch (error) {
			setFormError(
				error instanceof Error ? error.message : "Could not stop the recording.",
			);
		}
	};

	return (
		<View className="flex-1">
			<ScrollView
				className="flex-1"
				contentContainerClassName="px-8 py-5 gap-4"
				showsVerticalScrollIndicator
			>
				<View className="pb-4 border-b border-color gap-2">
					<Text className="text-[10px] font-semibold tracking-wide darker-text">
						SOURCE
					</Text>
					<Dropdown
						value={sourceID}
						options={sourceOptions}
						onValueChange={(value) => {
							setSourceID(String(value));
							setQualityHeight(null);
							setFilenameEdited(false);
						}}
						disabled={controlsDisabled}
						searchable={streams.length > 6}
						style={{ width: "100%" }}
					/>
					{sourceID === CUSTOM_SOURCE && (
						<TextInput
							autoFocus
							enableFocusRing={false}
								editable={!controlsDisabled}
							className="text-base text px-1 py-2 border-b border-color"
							value={customURL}
							onChangeText={setCustomURL}
							placeholder="https://www.dailymotion.com/video/…"
						/>
					)}
					{!!selectedStream && (
						<Text className="text-xs darker-text" numberOfLines={1} selectable>
							{selectedStream.url}
						</Text>
					)}
				</View>

				{inspectionStatus === "inspecting" && (
					<View className="py-5 items-center gap-1">
						<Text className="text font-medium">Reading the DVR window…</Text>
						<Text className="text-xs darker-text">
							yt-dlp is resolving the live media playlist
						</Text>
					</View>
				)}

				{inspection && (
					<>
						<View className="gap-2 pb-3 border-b border-color">
							<View className="flex-row items-center gap-2">
								<Text className="flex-1 text-lg font-semibold text" numberOfLines={1}>
									{inspection.title}
								</Text>
								<Text
									className={`text-[10px] font-bold ${
										inspection.isDVR ? "text-green-600" : "text-red-500"
									}`}
								>
									{inspection.isDVR ? "DVR LIVE" : "NOT DVR"}
								</Text>
							</View>
							{rangeStart && rangeEnd && (
								<>
									<View className="flex-row justify-between">
										<Text className="text-xs darker-text">
											{formatDetailedClock(rangeStart)}
										</Text>
										<Text className="text-xs darker-text">
											{formatDetailedClock(rangeEnd)}
										</Text>
									</View>
									<View className="h-1.5 bg-neutral-300 dark:bg-neutral-700 relative">
										<View
											className="absolute h-1.5 bg-accent-strong"
											style={{
												left: `${Math.max(0, selectionStartPercent)}%`,
												width: `${Math.max(
													0,
													Math.min(100, selectionEndPercent) -
														Math.max(0, selectionStartPercent),
												)}%`,
											}}
										/>
									</View>
					<Text className="text-xs darker-text text-center">
						{formatDuration(inspection.duration)} available · HLS segment precision
									</Text>
								</>
							)}
						</View>

						<View>
							<BoundaryRow
								label="Start"
								edgeLabel="DVR beginning"
								mode={startMode}
								clock={startClock}
								disabled={controlsDisabled}
								onModeChange={setStartMode}
								onClockChange={setStartClock}
							/>
							<BoundaryRow
								label="End"
								edgeLabel="DVR end"
								mode={endMode}
								clock={endClock}
								disabled={controlsDisabled}
								onModeChange={setEndMode}
								onClockChange={setEndClock}
							/>
						</View>

						<View className="flex-row gap-5 py-2 border-b border-color">
							<View className="flex-1 gap-1">
								<Text className="text-[10px] font-semibold tracking-wide darker-text">
									QUALITY
								</Text>
								<Dropdown
									value={qualityHeight == null ? "auto" : String(qualityHeight)}
									options={qualityOptions}
									onValueChange={(value) =>
										setQualityHeight(value === "auto" ? null : Number(value))
									}
									disabled={controlsDisabled}
									searchable={false}
									style={{ width: "100%" }}
								/>
							</View>
							<View className="flex-1 gap-1">
								<Text className="text-[10px] font-semibold tracking-wide darker-text">
									FILE NAME
								</Text>
								<TextInput
									enableFocusRing={false}
									editable={!controlsDisabled}
									className="text text-sm px-2 py-1.5 border-b border-color"
									value={filename}
									onChangeText={(value) => {
										setFilenameEdited(true);
										setFilename(value);
									}}
								/>
							</View>
						</View>

						<View className="flex-row items-center gap-3 py-2 border-b border-color">
							<View className="flex-1 gap-0.5">
								<Text className="text-[10px] font-semibold tracking-wide darker-text">
									DESTINATION
								</Text>
								<Text className="text-sm text" numberOfLines={1} selectable>
									{outputPath}
								</Text>
							</View>
							<TouchableOpacity
								disabled={controlsDisabled}
								className="px-3 py-2 rounded-md border border-color"
								onPress={() => void pickDestination()}
							>
								<Text className="text-xs">Choose…</Text>
							</TouchableOpacity>
						</View>

						<View className="flex-row justify-between gap-4">
							<Text className="text-xs darker-text">
								{selectedDuration > 0 ? formatDuration(selectedDuration) : "—"}
								{" · estimated "}
								{estimatedBytes > 0 ? prettyBytes(estimatedBytes) : "—"}
							</Text>
							<Text className={lacksDiskSpace ? "text-xs text-red-500" : "text-xs darker-text"}>
								{destinationCapacity == null
									? destinationCapacityError
										? "Free space unavailable"
										: "Checking free space…"
									: `${prettyBytes(destinationCapacity)} free`}
							</Text>
						</View>
					</>
				)}

				{active && (
					<View className="py-3 border-y border-color gap-2">
						<View className="flex-row justify-between gap-3">
							<Text className="text font-semibold">{recording.message ?? "Recording…"}</Text>
							<Text className="text-xs darker-text">
								{Math.round((recording.progress ?? 0) * 100)}%
							</Text>
						</View>
						<View className="h-1.5 bg-neutral-300 dark:bg-neutral-700">
							<View
								className="h-1.5 bg-red-500"
								style={{ width: `${Math.max(1, (recording.progress ?? 0) * 100)}%` }}
							/>
						</View>
						{!!recording.duration && (
							<Text className="text-xs darker-text">
								{formatDuration(recording.elapsed ?? 0)} / {formatDuration(recording.duration)}
							</Text>
						)}
					</View>
				)}

				{recording.status === "completed" && recording.outputPath && (
					<TouchableOpacity
						className="border-l-2 border-green-500 pl-3 py-1"
						onPress={() => solNative.revealFileInFinder(recording.outputPath ?? "")}
					>
						<Text className="text-sm font-semibold text-green-600 dark:text-green-400">
							Recording completed — reveal in Finder
						</Text>
						<Text className="text-xs darker-text mt-1" numberOfLines={1}>
							{recording.outputPath}
							{recording.bytes ? ` · ${prettyBytes(recording.bytes)}` : ""}
						</Text>
					</TouchableOpacity>
				)}

				{!!selection.error && inspection && (
					<Text className="text-sm text-red-500">{selection.error}</Text>
				)}
				{lacksDiskSpace && (
					<Text className="text-sm text-red-500">
						Not enough free space. Sol keeps a 256 MB safety margin.
					</Text>
				)}
				{destinationCapacityError && (
					<Text className="text-sm text-red-500">
						Sol could not verify free space at this destination.
					</Text>
				)}
				{inspection && !inspection.isDVR && (
					<Text className="text-sm text-red-500">
						This stream does not expose a live DVR window.
					</Text>
				)}
				{!!inspectionError && (
					<View className="border-l-2 border-red-500 pl-3 py-1 gap-1">
						<Text className="text-sm text-red-500">{inspectionError}</Text>
						<Text className="text-xs darker-text">
							yt-dlp, Python 3 and FFmpeg must be installed locally.
						</Text>
					</View>
				)}
				{!!(formError || recording.error) && (
					<Text className="text-sm text-red-500">
						{formError || recording.error}
					</Text>
				)}
			</ScrollView>

			<View className="px-8 py-3 border-t border-color">
				{active ? (
					<TouchableOpacity
						disabled={recording.status === "cancelling"}
						className="py-3 rounded-md items-center border border-red-500"
						onPress={() => void cancelRecording()}
					>
						<Text className="text-red-500 font-semibold">
							{recording.status === "cancelling"
								? "Cancelling…"
								: "Cancel and delete partial file"}
						</Text>
					</TouchableOpacity>
				) : (
					<TouchableOpacity
						disabled={!canRecord}
						className={`py-3 rounded-md items-center ${
							canRecord ? "bg-red-600" : "bg-neutral-500"
						}`}
						onPress={() => void startRecording()}
					>
						<Text className="text-white font-semibold">
							{isStarting
								? "Checking the current DVR window…"
								: inspectionStatus === "inspecting"
									? "Reading DVR…"
									: "Record selected range"}
						</Text>
					</TouchableOpacity>
				)}
			</View>
		</View>
	);
});
