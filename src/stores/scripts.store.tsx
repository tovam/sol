import { makeAutoObservable } from "mobx";
import { solNative } from "lib/SolNative";
import {
	parseScriptArgumentModeMetadata,
	parseScriptCommandMetadata,
} from "lib/scriptCommands";
import type { EmitterSubscription } from "react-native";
import { ItemType } from "./ui.store";
import type { IRootStore } from "store";

let folderWatcher:
	| ReturnType<typeof solNative.createFolderWatcher>
	| undefined;
let onShowListener: EmitterSubscription | undefined;

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

	return {
		name,
		icon,
		command: parseScriptCommandMetadata(content),
		argumentMode: parseScriptArgumentModeMetadata(content),
	};
}

export type ScriptsStore = ReturnType<typeof createScriptsStore>;

export const createScriptsStore = (_root: IRootStore) => {
	const scriptsPath = getScriptsPath();

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
				const execute = async (arguments_: string[] = []) => {
					try {
						if (file.endsWith(".applescript")) {
							await solNative.executeAppleScript(content);
						} else if (arguments_.length === 0) {
							await solNative.executeBashScript(content);
						} else {
							await solNative.executeBashScriptWithArguments(content, arguments_);
						}
					} catch (e) {
						solNative.showToast(`Error executing script ${e}`, "error");
					}
				};
				scriptItems.push({
					id: `script-${file}`,
					name: metadata.name,
					icon: metadata.icon,
					...(metadata.argumentMode == null
						? { subName: "Invalid # arguments header · expected raw or shlex" }
						: {}),
					type: ItemType.USER_SCRIPT,
					callback: () => execute(),
					...(command && metadata.argumentMode
						? {
								command,
								commandArgumentMode: metadata.argumentMode,
								commandCallback: (arguments_: string[]) => execute(arguments_),
							}
						: {}),
				});
			}
			store.scripts = scriptItems;
		},

		cleanUp() {
			onShowListener?.remove();
			onShowListener = undefined;
			if (folderWatcher) folderWatcher = undefined;
		},
	});

	// Keep the native HostObject alive for as long as the store exists. If it is
	// only held by a local variable, Hermes can collect it and silently stop the
	// FSEvents stream.
	folderWatcher = solNative.createFolderWatcher(scriptsPath, () => {
		store.loadScripts();
	});

	// Refreshing when Sol opens also covers changes made while it was asleep or
	// before the native watcher was ready.
	onShowListener = solNative.addListener("onShow", () => {
		store.loadScripts();
	});

	store.loadScripts();

	return store;
};
