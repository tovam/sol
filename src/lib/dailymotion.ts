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

export function dailymotionEmbedURL(videoID: string) {
	return `https://www.dailymotion.com/embed/video/${videoID}?autoplay=1&queue-enable=false&sharing-enable=false`;
}
