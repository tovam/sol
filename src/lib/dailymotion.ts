export type DailymotionStream = {
	id: string;
	name: string;
	url: string;
};

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
		streams.set(videoID, {
			id: videoID,
			name,
			url: record.url.trim(),
		});
	}
	return [...streams.values()];
}

export function dailymotionEmbedURL(videoID: string) {
	return `https://www.dailymotion.com/embed/video/${videoID}?autoplay=1&queue-enable=false&sharing-enable=false`;
}
