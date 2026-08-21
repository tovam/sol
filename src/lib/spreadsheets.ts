const createAliases = new Set(["sheet", "spreadsheet", "excel", "tableur"]);
const browseAliases = [
	"sheets",
	"tableurs",
	"open sheet",
	"open spreadsheet",
	"open tableur",
	"load sheet",
	"load spreadsheet",
	"load tableur",
	"ouvrir tableur",
	"charger tableur",
];

export type SpreadsheetCommand =
	| { kind: "create" }
	| { kind: "list"; filter: string };

export const resolveSpreadsheetCommand = (
	query: string,
): SpreadsheetCommand | null => {
	const trimmed = query.trim();
	const normalized = trimmed.toLocaleLowerCase();
	if (createAliases.has(normalized)) return { kind: "create" };
	for (const alias of browseAliases) {
		if (normalized === alias) return { kind: "list", filter: "" };
		if (normalized.startsWith(`${alias} `)) {
			return { kind: "list", filter: trimmed.slice(alias.length).trim() };
		}
	}
	return null;
};
