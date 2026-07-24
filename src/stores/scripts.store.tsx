import { solNative } from "lib/SolNative";
import {
	parseScriptArgumentModeMetadata,
	parseScriptCommandMetadata,
} from "lib/scriptCommands";
import {
	type IReactionDisposer,
	makeAutoObservable,
	reaction,
	toJS,
} from "mobx";
import type { EmitterSubscription } from "react-native";
import type { IRootStore } from "store";
import { getDefaultScriptsDirectoryPath } from "./config";
import { ItemType } from "./ui.store";

let folderWatchers: Array<
	ReturnType<typeof solNative.createFolderWatcher>
> = [];
let scriptDirectoriesDisposer: IReactionDisposer | undefined;
let onShowListener: EmitterSubscription | undefined;

const ALLOWED_SCRIPT_EXTENSIONS = [".sh", ".applescript"];

function parseScriptMetadata(content: string, fileName: string) {
	let name = fileName.replace(/\..*$/, "");
	let icon = "💻";

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

export const createScriptsStore = (root: IRootStore) => {
	const defaultScriptsDirectory = getDefaultScriptsDirectoryPath();
	const getScriptDirectories = () => [
		defaultScriptsDirectory,
		...toJS(root.ui.scriptDirectories),
	];

	const store = makeAutoObservable({
		scripts: [] as Item[],

		loadScripts() {
			const scriptItems: Item[] = [];

			for (const scriptsDirectory of getScriptDirectories()) {
				let files: string[];
				try {
					files = solNative.ls(scriptsDirectory);
				} catch (error) {
					console.error(
						`Could not read scripts directory ${scriptsDirectory}:`,
						error,
					);
					continue;
				}

				for (const file of files) {
					const lowerFileName = file.toLowerCase();
					if (
						!ALLOWED_SCRIPT_EXTENSIONS.some((extension) =>
							lowerFileName.endsWith(extension),
						)
					) {
						continue;
					}

					const fullPath = `${scriptsDirectory}/${file}`;
					const content = solNative.readFile(fullPath);
					if (!content) continue;

					const metadata = parseScriptMetadata(content, file);
					const isShellScript = lowerFileName.endsWith(".sh");
					const command = isShellScript
						? (metadata.command ?? undefined)
						: undefined;
					const execute = async (arguments_: string[] = []) => {
						try {
							if (lowerFileName.endsWith(".applescript")) {
								await solNative.executeAppleScript(content);
							} else {
								await solNative.executeUserScript(
									content,
									metadata.name,
									arguments_,
								);
							}
						} catch (error) {
							solNative.showToast(
								`Error executing script ${String(error)}`,
								"error",
							);
						}
					};
					const id =
						scriptsDirectory === defaultScriptsDirectory
							? `script-${file}`
							: `script-${encodeURIComponent(fullPath)}`;

					scriptItems.push({
						id,
						name: metadata.name,
						icon: metadata.icon,
						scriptPath: fullPath,
						...(metadata.argumentMode == null
							? {
									subName:
										"Invalid # arguments header · expected raw or shlex",
								}
							: {}),
						type: ItemType.USER_SCRIPT,
						callback: () => execute(),
						...(command && metadata.argumentMode
							? {
									command,
									commandArgumentMode: metadata.argumentMode,
									commandCallback: (
										arguments_: string[],
										_rawArgument: string,
									) => execute(arguments_),
								}
							: {}),
					});
				}
			}

			store.scripts = scriptItems;
		},

		cleanUp() {
			onShowListener?.remove();
			onShowListener = undefined;
			scriptDirectoriesDisposer?.();
			scriptDirectoriesDisposer = undefined;
			folderWatchers = [];
		},
	});

	const refreshFolderWatchers = () => {
		folderWatchers = [];
		for (const scriptsDirectory of getScriptDirectories()) {
			if (!solNative.exists(scriptsDirectory)) continue;
			try {
				folderWatchers.push(
					solNative.createFolderWatcher(scriptsDirectory, () => {
						store.loadScripts();
					}),
				);
			} catch (error) {
				console.error(
					`Could not watch scripts directory ${scriptsDirectory}:`,
					error,
				);
			}
		}
	};

	scriptDirectoriesDisposer = reaction(
		() => root.ui.scriptDirectories.slice(),
		() => {
			refreshFolderWatchers();
			store.loadScripts();
		},
		{ fireImmediately: true },
	);

	onShowListener = solNative.addListener("onShow", () => {
		store.loadScripts();
	});

	return store;
};
