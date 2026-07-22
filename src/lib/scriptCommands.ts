const SCRIPT_COMMAND_PATTERN = /^[A-Za-z0-9][A-Za-z0-9._-]*$/;
const RESERVED_SCRIPT_COMMANDS = new Set(["ai", "ia", "dm"]);

export type CommandArgumentMode = "raw" | "shlex";

export type ScriptCommandInvocation = {
	command: string;
	rawArgument: string;
};

export type ParsedCommandArguments =
	| { ok: true; arguments: string[] }
	| { ok: false; error: string };

export const parseScriptCommandMetadata = (content: string): string | null => {
	const candidate = content.match(/^#\s*command:\s*(.+)$/im)?.[1]?.trim();
	if (!candidate || !SCRIPT_COMMAND_PATTERN.test(candidate)) return null;
	if (RESERVED_SCRIPT_COMMANDS.has(candidate.toLowerCase())) return null;
	return candidate;
};

export const parseScriptArgumentModeMetadata = (
	content: string,
): CommandArgumentMode | null => {
	const candidate = content.match(/^#\s*arguments:\s*(.+)$/im)?.[1]?.trim();
	if (candidate == null) return "raw";
	const normalized = candidate.toLowerCase();
	return normalized === "raw" || normalized === "shlex" ? normalized : null;
};

export const parseScriptCommandInvocation = (
	query: string,
): ScriptCommandInvocation | null => {
	const normalizedQuery = query.trimStart();
	if (!normalizedQuery) return null;

	const separatorIndex = normalizedQuery.search(/\s/);
	if (separatorIndex === -1) {
		return { command: normalizedQuery.toLowerCase(), rawArgument: "" };
	}

	return {
		command: normalizedQuery.slice(0, separatorIndex).toLowerCase(),
		rawArgument: normalizedQuery.slice(separatorIndex).trimStart(),
	};
};

const isShlexWhitespace = (character: string) =>
	character === " " ||
	character === "\t" ||
	character === "\r" ||
	character === "\n";

/**
 * Parses the POSIX subset used by Python's shlex.split(..., posix=True):
 * whitespace separation, adjacent quoted fragments, empty quoted arguments,
 * and backslash escaping. Comment parsing is deliberately disabled.
 */
export const parseCommandArguments = (
	rawArgument: string,
	mode: CommandArgumentMode,
): ParsedCommandArguments => {
	if (!rawArgument) return { ok: true, arguments: [] };
	if (mode === "raw") return { ok: true, arguments: [rawArgument] };

	const arguments_: string[] = [];
	let token = "";
	let tokenStarted = false;
	let quote: "single" | "double" | null = null;

	for (let index = 0; index < rawArgument.length; index += 1) {
		const character = rawArgument[index];

		if (quote === "single") {
			if (character === "'") {
				quote = null;
			} else {
				token += character;
			}
			continue;
		}

		if (quote === "double") {
			if (character === '"') {
				quote = null;
				continue;
			}
			if (character === "\\") {
				const next = rawArgument[index + 1];
				if (next == null) {
					return {
						ok: false,
						error: "No escaped character after the final backslash.",
					};
				}
				if (next === '"' || next === "\\" || next === "$" || next === "`") {
					token += next;
				} else if (next !== "\n") {
					token += `\\${next}`;
				}
				index += 1;
				continue;
			}
			token += character;
			continue;
		}

		if (isShlexWhitespace(character)) {
			if (tokenStarted) {
				arguments_.push(token);
				token = "";
				tokenStarted = false;
			}
			continue;
		}

		tokenStarted = true;
		if (character === "'") {
			quote = "single";
			continue;
		}
		if (character === '"') {
			quote = "double";
			continue;
		}
		if (character === "\\") {
			const next = rawArgument[index + 1];
			if (next == null) {
				return {
					ok: false,
					error: "No escaped character after the final backslash.",
				};
			}
			if (next !== "\n") token += next;
			index += 1;
			continue;
		}
		token += character;
	}

	if (quote === "single") {
		return { ok: false, error: "No closing quotation for the single quote." };
	}
	if (quote === "double") {
		return { ok: false, error: "No closing quotation for the double quote." };
	}
	if (tokenStarted) arguments_.push(token);

	return { ok: true, arguments: arguments_ };
};
