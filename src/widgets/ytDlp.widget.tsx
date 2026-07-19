import { BackButton } from "components/BackButton";
import { solNative } from "lib/SolNative";
import prettyBytes from "pretty-bytes";
import { type FC, useCallback, useEffect, useRef, useState } from "react";
import {
	Clipboard,
	Image,
	ScrollView,
	Text,
	TouchableOpacity,
	View,
} from "react-native";
import { TextInput } from "react-native-macos";
import { useStore } from "store";
import { Widget } from "stores/ui.store";

type DownloadMode = "video" | "audio";
type JobStatus =
	| "idle"
	| "analyzing"
	| "ready"
	| "downloading"
	| "completed"
	| "error";

type FormatInfo = {
	filesize?: number;
	filesize_approx?: number;
};

type VideoMetadata = FormatInfo & {
	title?: string;
	uploader?: string;
	channel?: string;
	duration?: number;
	is_live?: boolean;
	live_status?: string;
	ext?: string;
	resolution?: string;
	width?: number;
	height?: number;
	fps?: number;
	view_count?: number;
	thumbnail?: string;
	thumbnails?: Array<{
		url?: string;
		width?: number;
		height?: number;
	}>;
	requested_formats?: FormatInfo[];
};

const DEFAULT_DESTINATION = `/Users/${solNative.userName()}/Downloads`;

function shellQuote(value: string) {
	return ["'", value.split("'").join("'\"'\"'"), "'"].join("");
}

function isSupportedURL(value: string) {
	return /^https?:\/\/\S+$/i.test(value.trim());
}

function formatDuration(seconds?: number) {
	if (seconds == null || !Number.isFinite(seconds)) return undefined;
	const total = Math.max(0, Math.round(seconds));
	const hours = Math.floor(total / 3600);
	const minutes = Math.floor((total % 3600) / 60);
	const remainingSeconds = total % 60;
	return [hours, minutes, remainingSeconds]
		.filter((_, index) => index > 0 || hours > 0)
		.map((part) => part.toString().padStart(2, "0"))
		.join(":");
}

function estimatedSize(metadata?: VideoMetadata) {
	if (metadata == null) return undefined;
	const directSize = metadata.filesize ?? metadata.filesize_approx;
	if (directSize != null) return directSize;

	const formatSizes = metadata.requested_formats
		?.map((format) => format.filesize ?? format.filesize_approx)
		.filter((size): size is number => size != null);
	return formatSizes?.length
		? formatSizes.reduce((total, size) => total + size, 0)
		: undefined;
}

function resolution(metadata?: VideoMetadata) {
	if (metadata == null) return undefined;
	if (metadata.resolution && metadata.resolution !== "audio only") {
		return metadata.resolution;
	}
	if (metadata.width && metadata.height) {
		return `${metadata.width}×${metadata.height}`;
	}
	return metadata.ext?.toUpperCase();
}

function liveStatus(metadata?: VideoMetadata) {
	if (metadata?.is_live || metadata?.live_status === "is_live")
		return "Live now";
	if (metadata?.live_status === "was_live") return "Replay";
	if (metadata?.live_status === "is_upcoming") return "Upcoming";
	return undefined;
}

function pickedDirectoryPath(value: string) {
	if (!value.startsWith("file://")) return value;
	try {
		return decodeURIComponent(new URL(value).pathname);
	} catch {
		return value.replace(/^file:\/\//, "");
	}
}

const STATUS_LABELS: Record<JobStatus, string> = {
	idle: "Waiting for a link",
	analyzing: "Reading metadata…",
	ready: "Ready",
	downloading: "Downloading…",
	completed: "Completed",
	error: "Error",
};

export const YtDlpWidget: FC = () => {
	const store = useStore();
	const [url, setURL] = useState("");
	const [mode, setMode] = useState<DownloadMode>("video");
	const [isAvailable, setIsAvailable] = useState<boolean | null>(null);
	const [status, setStatus] = useState<JobStatus>("idle");
	const [metadata, setMetadata] = useState<VideoMetadata>();
	const [error, setError] = useState("");
	const [destination, setDestination] = useState(DEFAULT_DESTINATION);
	const [downloadedPath, setDownloadedPath] = useState("");
	const analysisSequence = useRef(0);

	const checkAvailability = useCallback(async () => {
		try {
			const executable =
				await solNative.executeBashScriptWithOutput("command -v yt-dlp");
			setIsAvailable(Boolean(executable.trim()));
		} catch {
			setIsAvailable(false);
		}
	}, []);

	useEffect(() => {
		void checkAvailability();
		Clipboard.getString().then((clipboardText) => {
			if (isSupportedURL(clipboardText)) setURL(clipboardText.trim());
		});
	}, [checkAvailability]);

	useEffect(() => {
		const sequence = ++analysisSequence.current;
		const trimmedURL = url.trim();
		setDownloadedPath("");

		if (!isSupportedURL(trimmedURL) || isAvailable !== true) {
			setMetadata(undefined);
			setStatus("idle");
			return;
		}

		setStatus("analyzing");
		setError("");
		const timer = setTimeout(() => {
			const format = mode === "audio" ? "bestaudio/best" : "bv*+ba/b";
			const command = [
				"yt-dlp",
				"--dump-single-json",
				"--skip-download",
				"--no-playlist",
				"--no-warnings",
				"--format",
				shellQuote(format),
				shellQuote(trimmedURL),
			].join(" ");

			void solNative
				.executeBashScriptWithOutput(command)
				.then((output) => {
					if (analysisSequence.current !== sequence) return;
					setMetadata(JSON.parse(output.trim()) as VideoMetadata);
					setStatus("ready");
				})
				.catch((analysisError) => {
					if (analysisSequence.current !== sequence) return;
					setMetadata(undefined);
					setError(
						analysisError instanceof Error
							? analysisError.message
							: "Could not read video information",
					);
					setStatus("error");
				});
		}, 350);

		return () => clearTimeout(timer);
	}, [isAvailable, mode, url]);

	const pickDestination = async () => {
		try {
			const picked = await solNative.openFilePicker();
			if (picked) setDestination(pickedDirectoryPath(picked));
		} catch {
			// Closing the native picker is not an error.
		}
	};

	const download = async () => {
		if (!isSupportedURL(url)) {
			setError("Enter a valid http or https URL");
			return;
		}

		setError("");
		setDownloadedPath("");
		analysisSequence.current += 1;
		setStatus("downloading");
		const modeArguments =
			mode === "audio"
				? ["--extract-audio", "--audio-format", "mp3"]
				: ["--format", shellQuote("bv*+ba/b")];
		const command = [
			"yt-dlp",
			"--no-playlist",
			"--no-progress",
			...modeArguments,
			"-P",
			shellQuote(destination),
			"--print",
			shellQuote("after_move:%(filepath)s"),
			shellQuote(url.trim()),
		].join(" ");

		try {
			const output = await solNative.executeBashScriptWithOutput(command);
			const finalPath = output.trim().split("\n").filter(Boolean).at(-1) ?? "";
			setDownloadedPath(finalPath);
			setStatus("completed");
			void solNative.showToast("Download completed", "success");
		} catch (downloadError) {
			setError(
				downloadError instanceof Error
					? downloadError.message
					: "Download failed",
			);
			setStatus("error");
			void solNative.showToast("Download failed", "error");
		}
	};

	const size = estimatedSize(metadata);
	const creator = metadata?.uploader ?? metadata?.channel;
	const previewURL =
		metadata?.thumbnail ??
		metadata?.thumbnails?.filter(({ url: candidate }) => Boolean(candidate)).at(-1)
			?.url;
	const metadataFacts = [
		mode === "audio" ? "MP3" : resolution(metadata),
		formatDuration(metadata?.duration),
		size ? prettyBytes(size) : undefined,
		metadata?.fps ? `${metadata.fps} fps` : undefined,
		metadata?.view_count != null
			? `${metadata.view_count.toLocaleString()} views`
			: undefined,
		liveStatus(metadata),
	].filter((fact): fact is string => Boolean(fact));
	const statusColor =
		status === "completed"
			? "bg-green-500"
			: status === "error"
				? "bg-red-500"
				: status === "analyzing" || status === "downloading"
					? "bg-orange-500"
					: "bg-neutral-400";

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
					<Text className="text-xl font-semibold text">yt-dlp Downloader</Text>
					<View className="flex-row items-center gap-1.5">
						<View className={`w-2 h-2 rounded-full ${statusColor}`} />
						<Text className="text-xs darker-text">{STATUS_LABELS[status]}</Text>
					</View>
				</View>
			</View>

			<ScrollView
				className="flex-1"
				contentContainerClassName="px-8 py-5 gap-4"
				showsVerticalScrollIndicator
			>
				<View className="border-b border-color pb-3">
					<Text className="text-[10px] font-semibold tracking-wide darker-text">
						VIDEO URL
					</Text>
					<TextInput
						autoFocus
						enableFocusRing={false}
						className="text-lg text mt-1"
						value={url}
						onChangeText={setURL}
						editable={status !== "downloading"}
						onSubmitEditing={() => void download()}
						placeholder="Paste a supported video URL…"
					/>
				</View>

				<View className="flex-row border-b border-color">
					{(["video", "audio"] as const).map((nextMode) => (
						<TouchableOpacity
							key={nextMode}
							disabled={status === "downloading"}
							className={`flex-1 py-3 border-b-2 items-center ${
								mode === nextMode
									? "border-accent-strong"
									: "border-transparent"
							}`}
							onPress={() => setMode(nextMode)}
						>
							<Text
								className={
									mode === nextMode
										? "text-accent font-semibold"
										: "darker-text"
								}
							>
								{nextMode === "video" ? "Best video" : "MP3 audio"}
							</Text>
						</TouchableOpacity>
					))}
				</View>

				{metadata && (
					<View className="flex-row gap-5 py-2 min-h-36">
						{previewURL ? (
							<Image
								source={{ uri: previewURL }}
								className="w-60 h-36 rounded-md bg-neutral-200 dark:bg-neutral-800"
								resizeMode="cover"
								accessibilityLabel={metadata.title || "Video thumbnail"}
							/>
						) : (
							<View className="w-60 h-36 rounded-md bg-neutral-200 dark:bg-neutral-800 items-center justify-center">
								<Text className="text-3xl darker-text">▶</Text>
							</View>
						)}
						<View className="flex-1 py-1">
							<Text className="text-xl font-semibold text" numberOfLines={3}>
								{metadata.title || "Untitled media"}
							</Text>
							{!!creator && (
								<Text className="text-sm darker-text mt-1" numberOfLines={1}>
									{creator}
								</Text>
							)}
							{!!metadataFacts.length && (
								<Text className="text-sm darker-text mt-auto" selectable>
									{metadataFacts.join("  ·  ")}
								</Text>
							)}
						</View>
					</View>
				)}

				<View className="py-3 border-y border-color">
					<View className="flex-row items-center justify-between gap-3">
						<View className="flex-1 gap-0.5">
							<Text className="text-[10px] uppercase tracking-wide darker-text">
								Destination
							</Text>
							<Text
								className="text-sm font-medium"
								numberOfLines={1}
								selectable
							>
								{destination}
							</Text>
						</View>
						<TouchableOpacity
							className="px-3 py-2 rounded-md border border-color"
							disabled={status === "downloading"}
							onPress={() => void pickDestination()}
						>
							<Text className="text-xs">Choose…</Text>
						</TouchableOpacity>
					</View>
				</View>

				{!!downloadedPath && (
					<TouchableOpacity
						className="border-l-2 border-green-500 pl-3 py-1"
						onPress={() => solNative.openWithFinder(downloadedPath)}
					>
						<Text className="text-sm font-semibold text-green-600 dark:text-green-400">
							Download completed — reveal in Finder
						</Text>
						<Text className="text-xs darker-text mt-1" numberOfLines={1}>
							{downloadedPath}
						</Text>
					</TouchableOpacity>
				)}

				{!!error && (
					<View className="border-l-2 border-red-500 pl-3 py-1">
						<Text className="text-sm text-red-500">{error}</Text>
					</View>
				)}
				{isAvailable === false && (
					<View className="border-t border-orange-500/40 pt-4 gap-2">
						<Text className="text font-semibold">yt-dlp is not installed</Text>
						<Text className="text-sm darker-text">
							Install it with Homebrew, then check again.
						</Text>
						<View className="flex-row gap-2">
							<TouchableOpacity
								className="px-4 py-2 rounded-lg subBg border border-color"
								onPress={() => {
									void solNative.executeBashScript("brew install yt-dlp");
								}}
							>
								<Text className="text">Install with Homebrew</Text>
							</TouchableOpacity>
							<TouchableOpacity
								className="px-4 py-2 rounded-lg subBg border border-color"
								onPress={() => void checkAvailability()}
							>
								<Text className="text">Check again</Text>
							</TouchableOpacity>
						</View>
					</View>
				)}
			</ScrollView>

			<View className="px-8 py-4 border-t border-color">
				<TouchableOpacity
					className={`py-3 rounded-md items-center ${
						isAvailable && isSupportedURL(url) && status !== "downloading"
							? "bg-accent-strong"
							: "bg-neutral-500"
					}`}
					disabled={
						!isAvailable || !isSupportedURL(url) || status === "downloading"
					}
					onPress={() => void download()}
				>
					<Text className="text-white font-semibold">
						{status === "downloading"
							? "Downloading…"
							: isAvailable === null
								? "Checking yt-dlp…"
								: "Download"}
					</Text>
				</TouchableOpacity>
			</View>
		</View>
	);
};
