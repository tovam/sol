const SCRIPT_COMMAND_PATTERN = /^[A-Za-z0-9][A-Za-z0-9._-]*$/;
const RESERVED_SCRIPT_COMMANDS = new Set(["ai", "ia", "dm"]);

export type ScriptCommandInvocation = {
	command: string;
	argument: string;
};

export const parseScriptCommandMetadata = (content: string): string | null => {
	const candidate = content.match(/^#\s*command:\s*(.+)$/im)?.[1]?.trim();
	if (!candidate || !SCRIPT_COMMAND_PATTERN.test(candidate)) return null;
	if (RESERVED_SCRIPT_COMMANDS.has(candidate.toLowerCase())) return null;
	return candidate;
};

export const parseScriptCommandInvocation = (
	query: string,
): ScriptCommandInvocation | null => {
	const normalizedQuery = query.trimStart();
	if (!normalizedQuery) return null;

	const separatorIndex = normalizedQuery.search(/\s/);
	if (separatorIndex === -1) {
		return { command: normalizedQuery.toLowerCase(), argument: "" };
	}

	return {
		command: normalizedQuery.slice(0, separatorIndex).toLowerCase(),
		argument: normalizedQuery.slice(separatorIndex).trimStart(),
	};
};
