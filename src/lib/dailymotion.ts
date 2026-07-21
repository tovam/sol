export type DailymotionStream = {
	id: string;
	name: string;
	url: string;
	command?: string;
};

export type DailymotionCommandResolution =
	| { kind: "none" }
	| { kind: "suggest"; streams: DailymotionStream[] }
	| { kind: "watch"; stream: DailymotionStream }
	| {
			kind: "record";
			stream: DailymotionStream;
			startClock: string;
			endClock: string;
	  }
	| { kind: "error"; message: string };

const DAILYMOTION_CLOCK_PATTERN =
	/^([01]\d|2[0-3]):([0-5]\d)(?::([0-5]\d))?$/;
const DAILYMOTION_DIRECT_COMMAND_PATTERN =
	/^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$/;
const RESERVED_DAILYMOTION_DIRECT_COMMANDS = new Set(["ai", "ia", "dm"]);
const DAILYMOTION_COMMAND_USAGE =
	"dm <favorite> rec HH:mm[:ss] HH:mm[:ss]";

function normalizeDailymotionFavoriteName(value: string) {
	return value
		.normalize("NFD")
		.replace(/[\u0300-\u036f]/g, "")
		.trim()
		.replace(/\s+/g, " ")
		.toLowerCase();
}

export function validateDailymotionDirectCommand(value: string) {
	const command = value.trim();
	if (!command) return null;
	if (!DAILYMOTION_DIRECT_COMMAND_PATTERN.test(command)) {
		return "Direct command must be 1–64 letters, numbers, dots, dashes or underscores";
	}
	if (RESERVED_DAILYMOTION_DIRECT_COMMANDS.has(command.toLowerCase())) {
		return `“${command}” is reserved by Sol`;
	}
	return null;
}

export function suggestDailymotionDirectCommand(name: string) {
	const base = normalizeDailymotionFavoriteName(name)
		.replace(/[^a-z0-9._-]+/g, "-")
		.replace(/^[^a-z0-9]+|[^a-z0-9]+$/g, "")
		.slice(0, 64);
	if (!base) return "";
	const candidate = RESERVED_DAILYMOTION_DIRECT_COMMANDS.has(base)
		? `${base}-live`
		: base;
	return validateDailymotionDirectCommand(candidate) == null ? candidate : "";
}

export function resolveDailymotionDirectCommand(
	query: string,
	streams: DailymotionStream[],
) {
	const command = query.trim();
	if (!DAILYMOTION_DIRECT_COMMAND_PATTERN.test(command)) return null;
	const normalizedCommand = command.toLowerCase();
	return (
		streams.find(
			(stream) => stream.command?.toLowerCase() === normalizedCommand,
		) ?? null
	);
}

function normalizeDailymotionClock(value: string) {
	const match = value.match(DAILYMOTION_CLOCK_PATTERN);
	if (!match) return null;
	return `${match[1]}:${match[2]}:${match[3] ?? "00"}`;
}

function exactDailymotionFavoriteMatches(
	streams: DailymotionStream[],
	name: string,
) {
	const normalizedName = normalizeDailymotionFavoriteName(name);
	return streams.filter(
		(stream) =>
			normalizeDailymotionFavoriteName(stream.name) === normalizedName,
	);
}

function resolveExactDailymotionFavorite(
	streams: DailymotionStream[],
	name: string,
): DailymotionStream | { kind: "error"; message: string } {
	const matches = exactDailymotionFavoriteMatches(streams, name);
	if (matches.length === 1) return matches[0];
	if (matches.length > 1) {
		return {
			kind: "error",
			message: `Several Dailymotion favorites are named “${name.trim()}”.`,
		};
	}
	return {
		kind: "error",
		message: `No Dailymotion favorite named “${name.trim()}”.`,
	};
}

export function resolveDailymotionCommand(
	query: string,
	streams: DailymotionStream[],
): DailymotionCommandResolution {
	const prefix = query.match(/^\s*dm(?:\s+(.*))?\s*$/i);
	if (!prefix) return { kind: "none" };

	const payload = prefix[1]?.trim() ?? "";
	if (!payload) return { kind: "suggest", streams };

	// Exact matches come first so a favorite containing the reserved word "rec"
	// can still be opened normally.
	const exactWatchMatches = exactDailymotionFavoriteMatches(streams, payload);
	if (exactWatchMatches.length === 1) {
		return { kind: "watch", stream: exactWatchMatches[0] };
	}
	if (exactWatchMatches.length > 1) {
		return {
			kind: "error",
			message: `Several Dailymotion favorites are named “${payload}”.`,
		};
	}

	const recording = payload.match(/^(.+)\s+rec\s+(\S+)\s+(\S+)$/i);
	if (recording) {
		const startClock = normalizeDailymotionClock(recording[2]);
		const endClock = normalizeDailymotionClock(recording[3]);
		if (!startClock || !endClock) {
			return {
				kind: "error",
				message: `Invalid time. Usage: ${DAILYMOTION_COMMAND_USAGE}`,
			};
		}
		const stream = resolveExactDailymotionFavorite(streams, recording[1]);
		if (!("id" in stream)) return stream;
		return {
			kind: "record",
			stream,
			startClock,
			endClock,
		};
	}

	if (/\s+rec(?:\s|$)/i.test(payload)) {
		return {
			kind: "error",
			message: `Incomplete command. Usage: ${DAILYMOTION_COMMAND_USAGE}`,
		};
	}

	const normalizedPayload = normalizeDailymotionFavoriteName(payload);
	const suggestions = streams.filter((stream) =>
		normalizeDailymotionFavoriteName(stream.name).includes(normalizedPayload),
	);
	if (suggestions.length > 0) {
		return { kind: "suggest", streams: suggestions };
	}

	return {
		kind: "error",
		message: `No Dailymotion favorite named “${payload}”.`,
	};
}

type ParsedDailymotionSource = {
	kind: "video" | "geoPlayer";
	videoID: string;
	url: URL;
};

function videoIDFromPathSegment(segment?: string) {
	return segment?.match(/^([a-z0-9]+)(?:[_-]|$)/i)?.[1] ?? null;
}

function parseDailymotionSource(input: string): ParsedDailymotionSource | null {
	let url: URL;
	try {
		url = new URL(input.trim());
	} catch {
		return null;
	}

	if (
		(url.protocol !== "https:" && url.protocol !== "http:") ||
		url.username ||
		url.password ||
		url.port
	) {
		return null;
	}

	const host = url.hostname.toLowerCase();
	const path = url.pathname.split("/").filter(Boolean);
	if (host === "dai.ly") {
		const videoID = videoIDFromPathSegment(path[0]);
		return videoID ? { kind: "video", videoID, url } : null;
	}

	if (host === "dailymotion.com" || host === "www.dailymotion.com") {
		const videoSegment =
			path[0] === "video"
				? path[1]
				: path[0] === "embed" && path[1] === "video"
					? path[2]
					: undefined;
		const videoID = videoIDFromPathSegment(videoSegment);
		return videoID ? { kind: "video", videoID, url } : null;
	}

	if (host === "geo.dailymotion.com") {
		const playerFile = path[0] === "player" ? path[1] : undefined;
		const playerID = playerFile?.match(/^([a-z0-9_-]+)\.html$/i)?.[1];
		const videoID = url.searchParams.get("video");
		if (playerID && videoID && /^[a-z0-9]+$/i.test(videoID)) {
			return { kind: "geoPlayer", videoID, url };
		}
	}

	return null;
}

export function extractDailymotionVideoID(input: string) {
	return parseDailymotionSource(input)?.videoID ?? null;
}

export function dailymotionPlayerURL(input: string) {
	const source = parseDailymotionSource(input);
	if (!source) return null;
	if (source.kind === "video") return dailymotionEmbedURL(source.videoID);

	source.url.protocol = "https:";
	source.url.hash = "";
	return source.url.toString();
}

export function normalizeDailymotionStreams(
	value: unknown,
): DailymotionStream[] {
	if (!Array.isArray(value)) return [];

	const streams = new Map<string, DailymotionStream>();
	for (const candidate of value) {
		if (candidate == null || typeof candidate !== "object") continue;
		const record = candidate as Record<string, unknown>;
		if (typeof record.url !== "string") continue;
		const videoID = extractDailymotionVideoID(record.url);
		if (!videoID) continue;
		const name =
			typeof record.name === "string" && record.name.trim()
				? record.name.trim()
				: `Dailymotion ${videoID}`;
		const commandCandidate =
			typeof record.command === "string" ? record.command.trim() : "";
		const command =
			commandCandidate &&
			validateDailymotionDirectCommand(commandCandidate) == null
				? commandCandidate
				: undefined;
		streams.set(videoID, {
			id: videoID,
			name,
			url: record.url.trim(),
			...(command ? { command } : {}),
		});
	}

	const usedCommands = new Set<string>();
	return [...streams.values()].map((stream) => {
		if (!stream.command) return stream;
		const normalizedCommand = stream.command.toLowerCase();
		if (usedCommands.has(normalizedCommand)) {
			return { id: stream.id, name: stream.name, url: stream.url };
		}
		usedCommands.add(normalizedCommand);
		return stream;
	});
}

export function dailymotionEmbedURL(videoID: string) {
	return `https://www.dailymotion.com/embed/video/${videoID}?autoplay=1&queue-enable=false&sharing-enable=false`;
}
