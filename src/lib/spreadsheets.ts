const createAliases = ["sheet", "spreadsheet", "excel", "tableur"];
const createAliasSet = new Set(createAliases);
const browseAliases = [
	...createAliases,
	"sheets",
	"spreadsheets",
	"tableurs",
	"open sheet",
	"open sheets",
	"open spreadsheet",
	"open spreadsheets",
	"open excel",
	"open tableur",
	"open tableurs",
	"load sheet",
	"load sheets",
	"load spreadsheet",
	"load spreadsheets",
	"load excel",
	"load tableur",
	"load tableurs",
	"reopen sheet",
	"reopen spreadsheet",
	"reopen excel",
	"reopen tableur",
	"ouvrir tableur",
	"ouvrir tableurs",
	"charger tableur",
	"charger tableurs",
].sort((left, right) => right.length - left.length);

export type SpreadsheetCommand =
	| { kind: "create" }
	| { kind: "list"; filter: string };

export const resolveSpreadsheetCommand = (
	query: string,
): SpreadsheetCommand | null => {
	const trimmed = query.trim();
	const normalized = trimmed.toLocaleLowerCase();
	if (createAliasSet.has(normalized)) return { kind: "create" };
	for (const alias of browseAliases) {
		if (normalized === alias) return { kind: "list", filter: "" };
		if (normalized.startsWith(`${alias} `)) {
			return { kind: "list", filter: trimmed.slice(alias.length).trim() };
		}
	}
	return null;
};
