export type RaycastScriptMode =
	| "silent"
	| "compact"
	| "fullOutput"
	| "inline";

export type RaycastScriptMetadata = {
	schemaVersion: string;
	title: string | null;
	mode: RaycastScriptMode | null;
	rawMode: string | null;
	icon: string | null;
	packageName: string | null;
	author: string | null;
	authorURL: string | null;
	description: string | null;
};

export const RAYCAST_SCRIPT_EXTENSIONS = [
	".sh",
	".bash",
	".zsh",
	".fish",
	".command",
	".py",
	".rb",
	".js",
	".ts",
	".swift",
	".pl",
	".applescript",
] as const;

const RAYCAST_MODES = new Map<string, RaycastScriptMode>([
	["silent", "silent"],
	["compact", "compact"],
	["fulloutput", "fullOutput"],
	["inline", "inline"],
]);

const readRaycastField = (content: string, field: string): string | null => {
	const escapedField = field.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
	const value = content.match(
		new RegExp(`^\\s*#\\s*@raycast\\.${escapedField}\\s+(.+?)\\s*$`, "im"),
	)?.[1];
	return value?.trim() || null;
};

export const parseRaycastScriptMetadata = (
	content: string,
): RaycastScriptMetadata | null => {
	const schemaVersion = readRaycastField(content, "schemaVersion");
	if (!schemaVersion) return null;

	const rawMode = readRaycastField(content, "mode");
	return {
		schemaVersion,
		title: readRaycastField(content, "title"),
		mode: rawMode ? (RAYCAST_MODES.get(rawMode.toLowerCase()) ?? null) : null,
		rawMode,
		icon: readRaycastField(content, "icon"),
		packageName: readRaycastField(content, "packageName"),
		author: readRaycastField(content, "author"),
		authorURL: readRaycastField(content, "authorURL"),
		description: readRaycastField(content, "description"),
	};
};

export const resolveRelativeScriptPath = (
	scriptsDirectory: string,
	path: string,
): string => {
	const candidate = path.startsWith("/")
		? path
		: `${scriptsDirectory}/${path.replace(/^\.\//, "")}`;
	const parts: string[] = [];

	for (const part of candidate.split("/")) {
		if (!part || part === ".") continue;
		if (part === "..") {
			parts.pop();
			continue;
		}
		parts.push(part);
	}

	return `/${parts.join("/")}`;
};

export const raycastIconLooksLikePath = (icon: string): boolean =>
	icon.startsWith("/") ||
	icon.startsWith("./") ||
	icon.startsWith("../") ||
	/\.(?:icns|png|jpe?g|gif|webp|svg)$/i.test(icon);
