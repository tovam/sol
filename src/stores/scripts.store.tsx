import { solNative } from "lib/SolNative";
import {
	parseScriptArgumentModeMetadata,
	parseScriptCommandMetadata,
} from "lib/scriptCommands";
import {
	parseRaycastScriptMetadata,
	RAYCAST_SCRIPT_EXTENSIONS,
	raycastIconLooksLikePath,
	resolveRelativeScriptPath,
} from "lib/raycastScript";
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

function parseScriptMetadata(
	content: string,
	fileName: string,
	scriptsDirectory: string,
) {
	let name = fileName.replace(/\..*$/, "");
	let icon: string | undefined = "💻";
	let iconImage: { uri: string } | undefined;
	let iconError: string | null = null;
	const raycast = parseRaycastScriptMetadata(content);

	const nameMatch = content.match(/^#\s*name:\s*(.+)$/im);
	if (raycast?.title) name = raycast.title;
	if (nameMatch) name = nameMatch[1].trim();

	const iconMatch = content.match(/^#\s*icon:\s*(.+)$/im);
	const iconValue = iconMatch?.[1]?.trim() || raycast?.icon;
	if (iconValue) {
		if (!iconMatch && raycastIconLooksLikePath(iconValue)) {
			const iconPath = resolveRelativeScriptPath(scriptsDirectory, iconValue);
			if (solNative.exists(iconPath)) {
				icon = undefined;
				iconImage = { uri: encodeURI(`file://${iconPath}`) };
			} else {
				iconError = `Raycast icon not found: ${iconValue}`;
			}
		} else {
			icon = iconValue;
		}
	}

	return {
		name,
		icon,
		iconImage,
		iconError,
		raycast,
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
						!RAYCAST_SCRIPT_EXTENSIONS.some((extension) =>
							lowerFileName.endsWith(extension),
						)
					) {
						continue;
					}

					const fullPath = `${scriptsDirectory}/${file}`;
					const content = solNative.readFile(fullPath);
					if (!content) continue;

					const metadata = parseScriptMetadata(
						content,
						file,
						scriptsDirectory,
					);
					const isAppleScript = lowerFileName.endsWith(".applescript");
					const command = !isAppleScript
						? (metadata.command ?? undefined)
						: undefined;
					const execute = async (arguments_: string[] = []) => {
						try {
							if (isAppleScript) {
								await solNative.executeAppleScript(content);
							} else {
								await solNative.executeScriptFile(
									fullPath,
									metadata.name,
									arguments_,
									metadata.raycast?.mode !== "silent",
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
					const metadataDetails: string[] = [];
					if (metadata.argumentMode == null) {
						metadataDetails.push(
							"Invalid # arguments header · expected raw or shlex",
						);
					}
					if (metadata.raycast) {
						if (metadata.raycast.schemaVersion !== "1") {
							metadataDetails.push(
								`Unsupported Raycast schema ${metadata.raycast.schemaVersion}`,
							);
						}
						if (!metadata.raycast.title) {
							metadataDetails.push("Raycast script is missing @raycast.title");
						}
						if (!metadata.raycast.mode) {
							metadataDetails.push(
								metadata.raycast.rawMode
									? `Unsupported Raycast mode: ${metadata.raycast.rawMode}`
									: "Raycast script is missing @raycast.mode",
							);
						}
						if (metadata.raycast.packageName) {
							metadataDetails.push(metadata.raycast.packageName);
						}
						if (metadata.raycast.description) {
							metadataDetails.push(metadata.raycast.description);
						}
					}
					if (metadata.iconError) metadataDetails.push(metadata.iconError);

					scriptItems.push({
						id,
						name: metadata.name,
						icon: metadata.icon,
						iconImage: metadata.iconImage,
						scriptPath: fullPath,
						...(metadataDetails.length > 0
							? { subName: metadataDetails.join(" · ") }
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
