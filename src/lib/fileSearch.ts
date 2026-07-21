export type TextSelection = {
	start: number;
	end: number;
};

export type FileSearchEdit = {
	kind: "boundary-insertion" | "selection-deletion" | "deletion" | "other";
	nextSelection: TextSelection;
};

const WORD_CHARACTER = /^[\p{L}\p{N}\p{M}_]+$/u;
const LETTER = /^\p{L}\p{M}*$/u;

const graphemeSegmenter = (() => {
	const Segmenter = (
		Intl as typeof Intl & {
			Segmenter?: new (
				locales?: string | string[],
				options?: { granularity: "grapheme" },
			) => {
				segment: (value: string) => Iterable<{ index: number; segment: string }>;
			};
		}
	).Segmenter;

	return Segmenter
		? new Segmenter(undefined, { granularity: "grapheme" })
		: null;
})();

const clampSelection = (
	selection: TextSelection,
	textLength: number,
): TextSelection => {
	const start = Math.min(Math.max(selection.start, 0), textLength);
	const end = Math.min(Math.max(selection.end, start), textLength);
	return { start, end };
};

const graphemes = (value: string) => {
	if (graphemeSegmenter) {
		return Array.from(graphemeSegmenter.segment(value));
	}

	let offset = 0;
	return Array.from(value, (segment) => {
		const entry = { index: offset, segment };
		offset += segment.length;
		return entry;
	});
};

const previousGraphemeStart = (value: string, offset: number) => {
	let previous = offset;
	for (const entry of graphemes(value)) {
		if (entry.index >= offset) break;
		previous = entry.index;
	}
	return previous;
};

const nextGraphemeEnd = (value: string, offset: number) => {
	for (const entry of graphemes(value)) {
		if (entry.index >= offset) {
			return entry.index + entry.segment.length;
		}
	}
	return offset;
};

const graphemeBefore = (value: string, offset: number) => {
	const start = previousGraphemeStart(value, offset);
	return start === offset ? "" : value.slice(start, offset);
};

const graphemeAfter = (value: string, offset: number) => {
	const end = nextGraphemeEnd(value, offset);
	return end === offset ? "" : value.slice(offset, end);
};

const isWordCharacter = (value: string) => WORD_CHARACTER.test(value);

const inferredSelectionAfterEdit = (previous: string, next: string) => {
	let prefixLength = 0;
	while (
		prefixLength < previous.length &&
		prefixLength < next.length &&
		previous[prefixLength] === next[prefixLength]
	) {
		prefixLength += 1;
	}

	let previousSuffixStart = previous.length;
	let nextSuffixStart = next.length;
	while (
		previousSuffixStart > prefixLength &&
		nextSuffixStart > prefixLength &&
		previous[previousSuffixStart - 1] === next[nextSuffixStart - 1]
	) {
		previousSuffixStart -= 1;
		nextSuffixStart -= 1;
	}

	return { start: nextSuffixStart, end: nextSuffixStart };
};

export const normalizeFileSearchText = (value: string) =>
	value
		.normalize("NFKD")
		.replace(/\p{M}/gu, "")
		.toLocaleLowerCase("en-US")
		.trim();

export const fileNameMatchesQuery = (name: string, query: string) => {
	const normalizedQuery = normalizeFileSearchText(query);
	return (
		normalizedQuery.length > 0 &&
		normalizeFileSearchText(name).includes(normalizedQuery)
	);
};

export const analyzeFileSearchEdit = (
	previous: string,
	next: string,
	selectionBefore: TextSelection,
): FileSearchEdit => {
	const selection = clampSelection(selectionBefore, previous.length);
	const retainedLength = previous.length - (selection.end - selection.start);
	const insertedLength = next.length - retainedLength;
	const inserted =
		insertedLength >= 0
			? next.slice(selection.start, selection.start + insertedLength)
			: "";
	const followsSelection =
		insertedLength >= 0 &&
		next ===
			previous.slice(0, selection.start) +
			inserted +
			previous.slice(selection.end);
	const nextSelection = followsSelection
		? {
				start: selection.start + inserted.length,
				end: selection.start + inserted.length,
			}
		: inferredSelectionAfterEdit(previous, next);

	if (
		followsSelection &&
		selection.start !== selection.end &&
		inserted.length === 0
	) {
		return { kind: "selection-deletion", nextSelection };
	}

	if (
		followsSelection &&
		selection.start === selection.end &&
		graphemes(inserted).length === 1 &&
		LETTER.test(inserted)
	) {
		const before = graphemeBefore(previous, selection.start);
		const after = graphemeAfter(previous, selection.start);
		const isAtWordStart = !isWordCharacter(before) && isWordCharacter(after);
		const isAtWordEnd = isWordCharacter(before) && !isWordCharacter(after);

		if (isAtWordStart || isAtWordEnd) {
			return { kind: "boundary-insertion", nextSelection };
		}
	}

	if (next.length < previous.length) {
		return { kind: "deletion", nextSelection };
	}

	return { kind: "other", nextSelection };
};

export const getLikelyDeletionQueries = (
	query: string,
	selectionValue: TextSelection,
) => {
	const selection = clampSelection(selectionValue, query.length);
	if (selection.start !== selection.end) {
		return [query.slice(0, selection.start) + query.slice(selection.end)];
	}

	const candidates: string[] = [];
	const backspaceStart = previousGraphemeStart(query, selection.start);
	if (backspaceStart < selection.start) {
		candidates.push(
			query.slice(0, backspaceStart) + query.slice(selection.start),
		);
	}

	const deleteEnd = nextGraphemeEnd(query, selection.start);
	if (deleteEnd > selection.start) {
		candidates.push(query.slice(0, selection.start) + query.slice(deleteEnd));
	}

	return [...new Set(candidates)];
};
