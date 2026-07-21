import { makeAutoObservable } from "mobx";
import { solNative } from "lib/SolNative";
import { parseScriptCommandMetadata } from "lib/scriptCommands";
import { ItemType } from "./ui.store";
import type { IRootStore } from "store";

const getScriptsPath = () =>
	`/Users/${solNative.userName()}/.config/sol/scripts`;

function parseScriptMetadata(content: string, fileName: string) {
	// Default values
	let name = fileName.replace(/\..*$/, "");
	let icon = "💻";

	// Try to extract metadata from comments
	const nameMatch = content.match(/^#\s*name:\s*(.+)$/im);
	if (nameMatch) name = nameMatch[1].trim();
	const iconMatch = content.match(/^#\s*icon:\s*(.+)$/im);
	if (iconMatch) icon = iconMatch[1].trim();

	return { name, icon, command: parseScriptCommandMetadata(content) };
}

export type ScriptsStore = ReturnType<typeof createScriptsStore>;

export const createScriptsStore = (_root: IRootStore) => {
	const scriptsPath = getScriptsPath();
	const _folderWatcher = solNative.createFolderWatcher(scriptsPath, () => {
		store.loadScripts();
	});

	const store = makeAutoObservable({
		scripts: [] as Item[],

		loadScripts() {
			const files = solNative.ls(scriptsPath);
			const scriptItems: Item[] = [];
			const allowedExtensions = [
				// '.sh', '.py', '.js', '.ts', '.rb', '.pl', '.command', '.applescript', '.scpt', '.zsh', '.bash'
				".sh",
				".applescript",
			];
			for (const file of files) {
				const fullPath = `${scriptsPath}/${file}`;
				// Only consider files with allowed script extensions
				if (!allowedExtensions.some((ext) => file.endsWith(ext))) continue;
				const content = solNative.readFile(fullPath);
				if (!content) continue;
				const metadata = parseScriptMetadata(content, file);
				const command = file.endsWith(".sh")
					? (metadata.command ?? undefined)
					: undefined;
				const execute = async (argument?: string) => {
					try {
						if (file.endsWith(".applescript")) {
							await solNative.executeAppleScript(content);
						} else if (argument === undefined) {
							await solNative.executeBashScript(content);
						} else {
							await solNative.executeBashScriptWithArguments(content, [
								argument,
							]);
						}
					} catch (e) {
						solNative.showToast(`Error executing script ${e}`, "error");
					}
				};
				scriptItems.push({
					id: `script-${file}`,
					name: metadata.name,
					icon: metadata.icon,
					type: ItemType.USER_SCRIPT,
					callback: () => execute(),
					...(command
						? {
								command,
								commandCallback: (argument: string) => execute(argument),
							}
						: {}),
				});
			}
			store.scripts = scriptItems;
		},
	});

	// Initial load
	store.loadScripts();

	// Watch for changes

	return store;
};
