export type DailymotionStream = {
	id: string;
	name: string;
	url: string;
};

export function extractDailymotionVideoID(input: string) {
	const value = input.trim();
	const fullURL = value.match(
		/^https?:\/\/(?:www\.)?dailymotion\.com\/(?:embed\/)?video\/([a-z0-9]+)(?:[_/?#-]|$)/i,
	);
	if (fullURL?.[1]) return fullURL[1];
	const shortURL = value.match(
		/^https?:\/\/(?:www\.)?dai\.ly\/([a-z0-9]+)(?:[/?#-]|$)/i,
	);
	return shortURL?.[1] ?? null;
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
