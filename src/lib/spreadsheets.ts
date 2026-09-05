const createAliases = ["sheet", "spreadsheet", "excel", "tableur"];
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

export type SpreadsheetCommand = {
	kind: "list";
	filter: string;
	includesCreate: boolean;
};

export const resolveSpreadsheetCommand = (
	query: string,
): SpreadsheetCommand | null => {
	const trimmed = query.trim();
	const normalized = trimmed.toLocaleLowerCase();
	if (createAliases.includes(normalized)) {
		return { kind: "list", filter: "", includesCreate: true };
	}
	for (const alias of browseAliases) {
		if (normalized === alias) {
			return { kind: "list", filter: "", includesCreate: false };
		}
		if (normalized.startsWith(`${alias} `)) {
			return {
				kind: "list",
				filter: trimmed.slice(alias.length).trim(),
				includesCreate: false,
			};
		}
	}
	return null;
};
