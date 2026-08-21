const createAliases = new Set(["sheet", "spreadsheet", "excel", "tableur"]);

export type SpreadsheetCommand =
	| { kind: "create" }
	| { kind: "list"; filter: string };

export const resolveSpreadsheetCommand = (
	query: string,
): SpreadsheetCommand | null => {
	const trimmed = query.trim();
	const normalized = trimmed.toLocaleLowerCase();
	if (createAliases.has(normalized)) return { kind: "create" };
	if (normalized === "sheets") return { kind: "list", filter: "" };
	if (normalized.startsWith("sheets ")) {
		return { kind: "list", filter: trimmed.slice(7).trim() };
	}
	return null;
};
