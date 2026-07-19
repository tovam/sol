export type AIModelInfo = {
	id: string;
	name: string;
	meta?: Record<string, unknown>;
};

function asRecord(value: unknown): Record<string, unknown> | null {
	return typeof value === "object" && value !== null
		? (value as Record<string, unknown>)
		: null;
}

function nonEmptyString(value: unknown) {
	return typeof value === "string" && value.trim() ? value.trim() : null;
}

function collectStringValues(value: unknown, output: string[]) {
	if (typeof value === "string") {
		output.push(value);
		return;
	}
	if (Array.isArray(value)) {
		for (const item of value) collectStringValues(item, output);
		return;
	}
	const record = asRecord(value);
	if (!record) return;
	for (const item of Object.values(record)) collectStringValues(item, output);
}

function modelCorpus(model: AIModelInfo) {
	const metadata: string[] = [];
	collectStringValues(model.meta, metadata);
	return `${model.id} ${model.name} ${metadata.join(" ")}`.toLowerCase();
}

function modelIdentity(model: AIModelInfo) {
	return `${model.id} ${model.name}`.toLowerCase();
}

const NON_TEXT_MODEL_PATTERN =
	/(?:embed|rerank|whisper|transcrib|\btts\b|text[-_ ]to[-_ ]speech|speech[-_ ]to[-_ ]text|\baudio\b|moderation|computer[-_ ]use|deep[-_ ]research|search[-_ ]preview|\brealtime\b|\bsora\b|\bvideo\b)/i;

const IMAGE_GENERATION_PATTERN =
	/(?:image[-_ ]generation|text[-_ ]to[-_ ]image|stable[-_ ]diffusion|\bdiffusion\b|\bsdxl\b|\bflux(?:\b|[-_ ])|dall[-_ ]?e|\bdalle\b|\bimagen\b)/i;

function isExcludedNonTextModel(model: AIModelInfo) {
	const corpus = modelCorpus(model);
	if (NON_TEXT_MODEL_PATTERN.test(corpus)) return true;
	if (IMAGE_GENERATION_PATTERN.test(corpus)) return true;

	const identity = modelIdentity(model);
	const isVisualLanguageModel =
		/(?:^|[-_.:/ ])qwen[^ ]*[-_.:/]?vl(?:$|[-_.:/ 0-9])/.test(identity) ||
		/visual[-_ ]language|vision[-_ ]language/.test(corpus);
	return /(?:^|[-_.:/ ])image(?:$|[-_.:/ 0-9])/.test(identity) && !isVisualLanguageModel;
}

/** Parses the `{ data: [...] }` shape returned by OpenAI and OpenWebUI. */
export function parseAIModelsResponse(value: unknown): AIModelInfo[] {
	const root = asRecord(value);
	if (!root || !Array.isArray(root.data)) return [];

	const models: AIModelInfo[] = [];
	const seen = new Set<string>();
	for (const value of root.data) {
		const model = asRecord(value);
		const id = nonEmptyString(model?.id);
		if (!model || !id || seen.has(id)) continue;

		const info = asRecord(model.info);
		const directMeta = asRecord(model.meta);
		const nestedMeta = asRecord(info?.meta);
		const meta =
			directMeta || nestedMeta
				? { ...(nestedMeta ?? {}), ...(directMeta ?? {}) }
				: undefined;
		const metaName = nonEmptyString(meta?.name);
		const name =
			nonEmptyString(model.name) ?? nonEmptyString(info?.name) ?? metaName ?? id;
		models.push({ id, name, ...(meta ? { meta } : {}) });
		seen.add(id);
	}
	return models;
}

/** Keeps general-purpose OpenAI text/reasoning models usable by the Responses API. */
export function filterOpenAITextModels(models: AIModelInfo[]) {
	return models.filter((model) => {
		if (isExcludedNonTextModel(model)) return false;
		const identity = modelIdentity(model);
		return (
			/(?:^|:)gpt-/.test(identity) ||
			/(?:^|:)chatgpt-/.test(identity) ||
			/(?:^|:)chat-latest(?:\s|$)/.test(identity) ||
			/(?:^|:)codex-/.test(identity) ||
			/(?:^|:)o\d(?:-|$)/.test(identity)
		);
	});
}

/**
 * Keeps OpenWebUI text models from the requested families. Visual-language
 * Qwen models remain available because they still produce text responses.
 */
export function filterOpenWebUITextModels(models: AIModelInfo[]) {
	return models.filter((model) => {
		const corpus = modelCorpus(model);
		const requestedFamily =
			/qwen|llama|deep[ ._-]*seek|(?:^|[/_.:\-\s])phi(?:\d|$|[/_.:\-\s])/.test(
				corpus,
			);
		if (!requestedFamily) {
			return false;
		}
		return !isExcludedNonTextModel(model);
	});
}
