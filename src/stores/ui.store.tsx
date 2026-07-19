import * as Sentry from "@sentry/react-native";
import { Assets } from "assets";
import { Parser } from "expr-eval";
import { CONSTANTS } from "lib/constants";
import {
	type DailymotionStream,
	extractDailymotionVideoID,
	normalizeDailymotionStreams,
} from "lib/dailymotion";
import { fetchPublicIPAddress } from "lib/publicIp";
import { type GlassAppearance, solNative } from "lib/SolNative";
import {
	defaultShortcuts,
	normalizeShortcut,
	normalizeShortcutMap,
} from "lib/shortcuts";
import { googleTranslate } from "lib/translator";
import { CALCULATOR_CONSTANT_VALUES } from "lib/unitExpression";
import MiniSearch from "minisearch";
import {
	autorun,
	type IReactionDisposer,
	makeAutoObservable,
	reaction,
	runInAction,
	toJS,
} from "mobx";
import {
	Appearance,
	type EmitterSubscription,
	type LayoutChangeEvent,
	Linking,
	type NativeEventSubscription,
} from "react-native";
import RNRestart from "react-native-restart-newarch";
import type { IRootStore } from "store";
import { PORTABLE_KEYS, UI_PERSISTED_KEYS } from "./config";
import { createBaseItems } from "./items";
import {
	readPersistedUIState,
	writePersistedUIState,
} from "./persisted-config";
import {
	createTextTemporaryResult,
	fetchFlightInfoFromWeb,
	formatExpressionResult,
	getInitials,
	parseFlightIdentifier,
	parseTimezoneConversion,
	parseUnitConversion,
	type TemporaryResult,
	traverse,
} from "./ui.store.helpers";

const exprParser = new Parser();

let onShowListener: EmitterSubscription | undefined;
let onHideListener: EmitterSubscription | undefined;
let onFileSearchListener: EmitterSubscription | undefined;
let onHotkeyListener: EmitterSubscription | undefined;
let onAppsChangedListener: EmitterSubscription | undefined;
let appareanceListener: NativeEventSubscription | undefined;
let bookmarksDisposer: IReactionDisposer | undefined;
let configDisposer: IReactionDisposer | undefined;

export enum Widget {
	ONBOARDING = "ONBOARDING",
	SEARCH = "SEARCH",
	CALENDAR = "CALENDAR",
	TRANSLATION = "TRANSLATION",
	SETTINGS = "SETTINGS",
	CREATE_ITEM = "CREATE_ITEM",
	GOOGLE_MAP = "GOOGLE_MAP",
	SCRATCHPAD = "SCRATCHPAD",
	EMOJIS = "EMOJIS",
	CLIPBOARD = "CLIPBOARD",
	PROCESSES = "PROCESSES",
	FILE_SEARCH = "FILE_SEARCH",
	COLOR_PICKER = "COLOR_PICKER",
	TIMER = "TIMER",
	DOCKER = "DOCKER",
	TMUX_CHEATSHEET = "TMUX_CHEATSHEET",
	PASSWORD_GENERATOR = "PASSWORD_GENERATOR",
	QR_CODE = "QR_CODE",
	YTDLP = "YTDLP",
	AI_ONE_SHOT = "AI_ONE_SHOT",
	AI_CHAT = "AI_CHAT",
	AI_HISTORY = "AI_HISTORY",
	DAILYMOTION = "DAILYMOTION",
	HISTORY = "HISTORY",
}

export enum ItemType {
	FILE = "FILE",
	APPLICATION = "APPLICATION",
	CONFIGURATION = "CONFIGURATION",
	CUSTOM = "CUSTOM",
	USER_SCRIPT = "USER_SCRIPT",
	TEMPORARY_RESULT = "TEMPORARY_RESULT",
	BOOKMARK = "BOOKMARK",
	PREFERENCE_PANE = "PREFERENCE_PANE",
}

export enum SearchTab {
	ALL = "ALL",
	APPLICATIONS = "APPLICATIONS",
	FILES = "FILES",
	ACTIONS = "ACTIONS",
}

export const SEARCH_TAB_ORDER = [
	SearchTab.ALL,
	SearchTab.APPLICATIONS,
	SearchTab.FILES,
	SearchTab.ACTIONS,
] as const;

export enum ScratchPadColor {
	SYSTEM = "SYSTEM",
	BLUE = "BLUE",
	ORANGE = "ORANGE",
}

export type SettingsSection =
	| "ABOUT"
	| "GENERAL"
	| "TRANSLATE"
	| "ITEMS"
	| "SCRIPTS"
	| "CALENDARS"
	| "AI"
	| "DAILYMOTION";

const minisearch = new MiniSearch({
	fields: ["name", "localizedName", "alias", "type"],
	storeFields: [
		"name",
		"localizedName",
		"icon",
		"iconName",
		"iconImage",
		"IconComponent",
		"color",
		"url",
		"preventClose",
		"type",
		"alias",
		"subName",
		"callback",
		"metaCallback",
		"isApplescript",
		"text",
		"shortcut",
		"isFavorite",
		"isRunning",
		"bookmarkFolder",
		"faviconFallback",
	],
	tokenize: (text: string) => text.toLowerCase().split(/[\s.-]+/),
});

const userName = solNative.userName();
const defaultSearchFolders = [
	`/Users/${userName}/Downloads`,
	`/Users/${userName}/Documents`,
	`/Users/${userName}/Desktop`,
	`/Users/${userName}/Pictures`,
	`/Users/${userName}/Movies`,
	`/Users/${userName}/Music`,
];

export type UIStore = ReturnType<typeof createUIStore>;
type SearchEngine = "google" | "bing" | "duckduckgo" | "perplexity" | "custom";

const itemsThatShouldShowWindow = [
	"emoji_picker",
	"clipboard_manager",
	"process_manager",
	"scratchpad",
];

type RankedItem = Item & {
	score?: number;
};

export const DEFAULT_GLASS_APPEARANCE: GlassAppearance = {
	style: "clear",
	cornerRadius: 24,
	tintColor: null,
	tintOpacity: 0,
};

const normalizeGlassAppearance = (value: unknown): GlassAppearance => {
	const source =
		value != null && typeof value === "object"
			? (value as Record<string, unknown>)
			: {};
	const parseConfigNumber = (rawValue: unknown, fallback: number) => {
		if (
			typeof rawValue !== "number" &&
			!(typeof rawValue === "string" && rawValue.trim() !== "")
		) {
			return fallback;
		}

		const parsedValue = Number(rawValue);
		return Number.isFinite(parsedValue) ? parsedValue : fallback;
	};
	const rawRadius = parseConfigNumber(
		source.cornerRadius,
		DEFAULT_GLASS_APPEARANCE.cornerRadius,
	);
	const rawOpacity = parseConfigNumber(
		source.tintOpacity,
		DEFAULT_GLASS_APPEARANCE.tintOpacity,
	);
	const rawTint =
		typeof source.tintColor === "string" ? source.tintColor.trim() : "";
	const tintColor = /^#[\dA-Fa-f]{6}$/.test(rawTint) ? rawTint : null;

	return {
		style: source.style === "regular" ? "regular" : "clear",
		cornerRadius: Math.min(Math.max(rawRadius, 0), 32),
		tintColor,
		tintOpacity: tintColor ? Math.min(Math.max(rawOpacity, 0), 1) : 0,
	};
};

export const createUIStore = (root: IRootStore) => {
	// Guards against spurious writes during hydrate/reload
	let isHydrating = false;
	let fileSearchRequestId = 0;

	const getSelectionCount = (item: Pick<Item, "id" | "name">) => {
		const countById = store.frequencies[item.id];
		if (typeof countById === "number") {
			return countById;
		}

		const legacyCount = store.frequencies[item.name];
		return typeof legacyCount === "number" ? legacyCount : 0;
	};

	const getSelectionTimestamp = (item: Pick<Item, "id">) => {
		const timestamp = store.selectionTimestamps[item.id];
		return typeof timestamp === "number" ? timestamp : 0;
	};

	const compareRankedItems = (left: RankedItem, right: RankedItem) => {
		const leftCount = getSelectionCount(left);
		const rightCount = getSelectionCount(right);
		const leftWasSelected = leftCount > 0;
		const rightWasSelected = rightCount > 0;

		if (leftWasSelected !== rightWasSelected) {
			return leftWasSelected ? -1 : 1;
		}

		const scoreDiff = (right.score ?? 0) - (left.score ?? 0);
		if (scoreDiff !== 0) {
			return scoreDiff;
		}

		const timestampDiff =
			getSelectionTimestamp(right) - getSelectionTimestamp(left);
		if (timestampDiff !== 0) {
			return timestampDiff;
		}

		if (rightCount !== leftCount) {
			return rightCount - leftCount;
		}

		return left.name.localeCompare(right.name, undefined, {
			sensitivity: "base",
		});
	};

	const getPersistedUISnapshot = () => {
		const snapshot: Record<string, any> = {};
		for (const key of UI_PERSISTED_KEYS) {
			snapshot[key] = toJS((store as any)[key]);
		}
		return snapshot;
	};

	const persistToJson = () => {
		if (isHydrating) return;

		try {
			writePersistedUIState(getPersistedUISnapshot());
		} catch (e) {
			Sentry.captureException(e);
		}
	};

	const applyShortcutNormalization = (shortcuts?: Record<string, string>) => {
		if (!shortcuts) {
			return defaultShortcuts;
		}

		return normalizeShortcutMap(shortcuts);
	};

	const hydrate = async () => {
		isHydrating = true;
		try {
			const src: Record<string, any> = (await readPersistedUIState()) ?? {};

			const hasPortableData = PORTABLE_KEYS.some(
				(key) => src[key] !== undefined,
			);

			if (Object.keys(src).length > 0) {
				runInAction(() => {
					if (src.frequencies) {
						const values = Object.values(src.frequencies);
						const maxValue = Math.max(...(values as number[]));
						if (maxValue > 100) {
							store.frequencies = Object.fromEntries(
								Object.entries(src.frequencies).map(([key, value]) => [
									key,
									Math.floor(((value as number) / maxValue) * 100),
								]),
							);
						} else {
							store.frequencies = src.frequencies;
						}
					}
					if (src.selectionTimestamps) {
						store.selectionTimestamps = src.selectionTimestamps;
					}
					// Config-backed UI state
					store.onboardingStep = src.onboardingStep ?? "v1_start";
					store.note = src.note ?? "";
					if (src.notes) {
						store.note = src.notes.reduce((acc: string, n: string) => {
							return `${acc}\n${n}`;
						}, "");
					}
					store.history = src.history ?? [];

					// Config.json is authoritative for persisted UI state
					store.firstTranslationLanguage = src.firstTranslationLanguage ?? "en";
					store.secondTranslationLanguage =
						src.secondTranslationLanguage ?? "de";
					store.thirdTranslationLanguage = src.thirdTranslationLanguage ?? null;
					store.customItems = src.customItems ?? [];
					store.globalShortcut = src.globalShortcut ?? "option";
					store.showWindowOn = src.showWindowOn ?? "screenWithFrontmost";
					store.glassAppearance = normalizeGlassAppearance(src.glassAppearance);
					store.calendarEnabled = src.calendarEnabled ?? true;
					store.showAllDayEvents = src.showAllDayEvents ?? true;
					store.launchAtLogin = src.launchAtLogin ?? true;
					store.mediaKeyForwardingEnabled =
						src.mediaKeyForwardingEnabled ?? true;
					store.showUpcomingEvent = src.showUpcomingEvent ?? true;
					store.scratchPadColor = src.scratchPadColor ?? ScratchPadColor.SYSTEM;
					store.searchFolders = src.searchFolders ?? defaultSearchFolders;
					store.searchEngine = src.searchEngine ?? "google";
					store.customSearchUrl =
						src.customSearchUrl ?? "https://google.com/search?q=%s";
					store.shortcuts = applyShortcutNormalization(src.shortcuts);
					store.showInAppBrowserBookMarks =
						src.showInAppBrowserBookMarks ?? true;
					store.hasDismissedGettingStarted =
						src.hasDismissedGettingStarted ?? false;
					store.hyperKeyEnabled = src.hyperKeyEnabled ?? false;
					store.disabledItemIds = src.disabledItemIds ?? [];
					store.dailymotionStreams = normalizeDailymotionStreams(
						src.dailymotionStreams,
					);

					// If JSON had portable data, user completed onboarding
					if (hasPortableData) {
						store.onboardingStep = "v1_completed";
					}

					if (
						store.onboardingStep !== "v1_completed" &&
						store.onboardingStep !== "v1_skipped"
					) {
						store.focusedWidget = Widget.ONBOARDING;
					}
				});

				solNative.setLaunchAtLogin(src.launchAtLogin ?? true);
				solNative.setGlobalShortcut(src.globalShortcut);
				solNative.setShowWindowOn(src.showWindowOn ?? "screenWithFrontmost");
				solNative.setGlassAppearance(toJS(store.glassAppearance));
				solNative.setMediaKeyForwardingEnabled(store.mediaKeyForwardingEnabled);
				solNative.setHyperKeyEnabled(store.hyperKeyEnabled);
				solNative.updateHotkeys(toJS(store.shortcuts));

				store.username = solNative.userName();
				store.getApps();
				store.migrateCustomItems();
			} else {
				runInAction(() => {
					store.focusedWidget = Widget.ONBOARDING;
				});
			}
		} finally {
			isHydrating = false;
		}
	};

	const reloadJsonConfig = async () => {
		isHydrating = true;
		try {
			const jsonConfig = await readPersistedUIState();
			if (!jsonConfig) return;
			runInAction(() => {
				if (jsonConfig.frequencies !== undefined)
					store.frequencies = jsonConfig.frequencies;
				if (jsonConfig.selectionTimestamps !== undefined)
					store.selectionTimestamps = jsonConfig.selectionTimestamps;
				if (jsonConfig.history !== undefined)
					store.history = jsonConfig.history;
				if (jsonConfig.note !== undefined) store.note = jsonConfig.note;
				if (jsonConfig.onboardingStep !== undefined)
					store.onboardingStep = jsonConfig.onboardingStep;
				if (jsonConfig.firstTranslationLanguage !== undefined)
					store.firstTranslationLanguage = jsonConfig.firstTranslationLanguage;
				if (jsonConfig.secondTranslationLanguage !== undefined)
					store.secondTranslationLanguage =
						jsonConfig.secondTranslationLanguage;
				if (jsonConfig.thirdTranslationLanguage !== undefined)
					store.thirdTranslationLanguage = jsonConfig.thirdTranslationLanguage;
				if (jsonConfig.globalShortcut !== undefined)
					store.globalShortcut = jsonConfig.globalShortcut;
				if (jsonConfig.showWindowOn !== undefined)
					store.showWindowOn = jsonConfig.showWindowOn;
				store.glassAppearance = normalizeGlassAppearance(
					jsonConfig.glassAppearance,
				);
				if (jsonConfig.calendarEnabled !== undefined)
					store.calendarEnabled = jsonConfig.calendarEnabled;
				if (jsonConfig.showAllDayEvents !== undefined)
					store.showAllDayEvents = jsonConfig.showAllDayEvents;
				if (jsonConfig.launchAtLogin !== undefined)
					store.launchAtLogin = jsonConfig.launchAtLogin;
				if (jsonConfig.mediaKeyForwardingEnabled !== undefined)
					store.mediaKeyForwardingEnabled =
						jsonConfig.mediaKeyForwardingEnabled;
				if (jsonConfig.showUpcomingEvent !== undefined)
					store.showUpcomingEvent = jsonConfig.showUpcomingEvent;
				if (jsonConfig.scratchPadColor !== undefined)
					store.scratchPadColor = jsonConfig.scratchPadColor;
				if (jsonConfig.searchFolders !== undefined)
					store.searchFolders = jsonConfig.searchFolders;
				if (jsonConfig.searchEngine !== undefined)
					store.searchEngine = jsonConfig.searchEngine;
				if (jsonConfig.customSearchUrl !== undefined)
					store.customSearchUrl = jsonConfig.customSearchUrl;
				if (jsonConfig.shortcuts !== undefined)
					store.shortcuts = applyShortcutNormalization(jsonConfig.shortcuts);
				if (jsonConfig.showInAppBrowserBookMarks !== undefined)
					store.showInAppBrowserBookMarks =
						jsonConfig.showInAppBrowserBookMarks;
				if (jsonConfig.hyperKeyEnabled !== undefined)
					store.hyperKeyEnabled = jsonConfig.hyperKeyEnabled;
				if (jsonConfig.customItems !== undefined)
					store.customItems = jsonConfig.customItems;
				if (jsonConfig.disabledItemIds !== undefined)
					store.disabledItemIds = jsonConfig.disabledItemIds;
				if (jsonConfig.dailymotionStreams !== undefined)
					store.dailymotionStreams = normalizeDailymotionStreams(
						jsonConfig.dailymotionStreams,
					);
			});
			// Re-apply native side effects
			solNative.setLaunchAtLogin(store.launchAtLogin);
			solNative.setGlobalShortcut(store.globalShortcut);
			solNative.setShowWindowOn(store.showWindowOn);
			solNative.setGlassAppearance(toJS(store.glassAppearance));
			solNative.setMediaKeyForwardingEnabled(store.mediaKeyForwardingEnabled);
			solNative.setHyperKeyEnabled(store.hyperKeyEnabled);
			solNative.updateHotkeys(toJS(store.shortcuts));
		} finally {
			isHydrating = false;
		}
	};

	const baseItems = createBaseItems(root);

	const store = makeAutoObservable({
		//    ____  _                              _     _
		//   / __ \| |                            | |   | |
		//  | |  | | |__  ___  ___ _ ____   ____ _| |__ | | ___  ___
		//  | |  | | '_ \/ __|/ _ \ '__\ \ / / _` | '_ \| |/ _ \/ __|
		//  | |__| | |_) \__ \  __/ |   \ V / (_| | |_) | |  __/\__ \
		//   \____/|_.__/|___/\___|_|    \_/ \__,_|_.__/|_|\___||___/
		username: "",
		note: "",
		isAccessibilityTrusted: false,
		calendarAuthorizationStatus: null as CalendarAuthorizationStatus | null,
		onboardingStep: "v1_start" as OnboardingStep,
		searchEngine: "google" as SearchEngine,
		customSearchUrl: "https://google.com/search?q=%s" as string,
		globalShortcut: "option" as "command" | "option" | "control",
		scratchpadShortcut: "command" as "command" | "option" | "none",
		clipboardManagerShortcut: "shift" as "shift" | "option" | "none",
		showWindowOn: "screenWithFrontmost" as
			| "screenWithFrontmost"
			| "screenWithCursor",
		glassAppearance: { ...DEFAULT_GLASS_APPEARANCE } as GlassAppearance,
		query: "",
		selectedIndex: 0,
		focusedWidget: Widget.SEARCH,
		aiHistoryReturnWidget: Widget.SEARCH as Widget,
		searchTab: SearchTab.ALL as SearchTab,
		settingsSection: "GENERAL" as SettingsSection,
		events: [] as INativeEvent[],
		customItems: [] as Item[],
		disabledItemIds: [] as string[],
		dailymotionStreams: [] as DailymotionStream[],
		editingCustomItem: null as Item | null,
		apps: [] as Item[],
		isLoading: false,
		isIndexing: false,
		indexedFileResults: [] as Item[],
		translationResults: [] as string[],
		frequencies: {} as Record<string, number>,
		selectionTimestamps: {} as Record<string, number>,
		temporaryResult: null as TemporaryResult | null,
		firstTranslationLanguage: "en" as string,
		secondTranslationLanguage: "de" as string,
		thirdTranslationLanguage: null as null | string,
		calendarEnabled: true,
		showAllDayEvents: true,
		launchAtLogin: true,
		hasFullDiskAccess: false,
		bookmarks: [] as Item[],
		mediaKeyForwardingEnabled: true,
		targetHeight: 64,
		isDarkMode: Appearance.getColorScheme() === "dark",
		history: [] as string[],
		showUpcomingEvent: true,
		scratchPadColor: ScratchPadColor.SYSTEM,
		searchFolders: [] as string[],
		shortcuts: defaultShortcuts as Record<string, string>,
		showInAppBrowserBookMarks: true,
		hoveredEventId: null as string | null,
		hasDismissedGettingStarted: false,
		isVisible: false,
		showKeyboardRecorder: false,
		keyboardRecorderSelectedItem: null as string | null,
		shortcutSearchMode: false,
		shortcutSearchFilter: null as string | null,
		confirmDialogShown: false,
		confirmCallback: null as (() => any) | null,
		confirmTitle: null as string | null,
		hyperKeyEnabled: false,
		//    _____                            _           _
		//   / ____|                          | |         | |
		//  | |     ___  _ __ ___  _ __  _   _| |_ ___  __| |
		//  | |    / _ \| '_ ` _ \| '_ \| | | | __/ _ \/ _` |
		//  | |___| (_) | | | | | | |_) | |_| | ||  __/ (_| |
		//   \_____\___/|_| |_| |_| .__/ \__,_|\__\___|\__,_|
		//                        | |
		//                        |_|
		get files(): Item[] {
			return store.indexedFileResults;
		},
		runFileSearch: async (query: string) => {
			const requestId = ++fileSearchRequestId;
			const isDedicatedFileSearch = store.focusedWidget === Widget.FILE_SEARCH;
			const isFileTab =
				store.focusedWidget === Widget.SEARCH && store.searchTab === SearchTab.FILES;

			if (!query.trim() || (!isDedicatedFileSearch && !isFileTab)) {
				runInAction(() => {
					store.indexedFileResults = [];
					store.isLoading = false;
				});
				return;
			}
			runInAction(() => {
				store.isLoading = true;
				store.indexedFileResults = [];
			});
			try {
				const results = await solNative.searchFilesIndexed(query);
				const requestIsCurrent =
					requestId === fileSearchRequestId &&
					store.query === query &&
					(store.focusedWidget === Widget.FILE_SEARCH ||
						(store.focusedWidget === Widget.SEARCH &&
							store.searchTab === SearchTab.FILES));
				if (!requestIsCurrent) return;

				runInAction(() => {
					store.indexedFileResults = results.map((f) => ({
						id: f.path,
						type: ItemType.FILE,
						name: f.name,
						url: f.path,
					}));
					store.isLoading = false;
				});
			} catch {
				if (requestId !== fileSearchRequestId) return;
				runInAction(() => {
					store.indexedFileResults = [];
					store.isLoading = false;
				});
			}
		},
		get items(): Item[] {
			const allItems = [
				...store.apps,
				...baseItems,
				...store.customItems,
				...root.scripts.scripts,
				...(store.showInAppBrowserBookMarks ? store.bookmarks : []),
			];

			// If the query is empty, return all items
			if (!store.query) {
				return [...allItems].sort(compareRankedItems);
			}

			if (minisearch.documentCount === 0) {
				minisearch.addAll(allItems);
			} else {
				for (const item of allItems) {
					if (!minisearch.has(item.id)) {
						minisearch.add(item);
					}
				}
			}

			const results = minisearch.search(store.query, {
				boost: {
					name: 2,
				},
				prefix: true,
				fuzzy: true,
			}) as unknown as RankedItem[];

			results.sort(compareRankedItems);

			const temporaryResultItems = store.temporaryResult
				? [{ id: "temporary", type: ItemType.TEMPORARY_RESULT, name: "" }]
				: [];

			const finalResults: Item[] = [
				...(CONSTANTS.LESS_VALID_URL.test(store.query)
					? [
							{
								id: "open_url",
								type: ItemType.CONFIGURATION,
								name: "Open URL",
								icon: "🌎",
								callback: () => {
									if (store.query.startsWith("https://")) {
										Linking.openURL(store.query);
									} else {
										Linking.openURL(`https://${store.query}`);
									}
								},
							},
						]
					: []),
				...temporaryResultItems,
				...results,
			];

			return finalResults;
		},
		get searchItems(): Item[] {
			if (store.searchTab === SearchTab.FILES) {
				return store.indexedFileResults;
			}

			const enabledItems = store.items.filter(
				(item) => !store.isItemDisabled(item.id),
			);
			if (store.searchTab === SearchTab.APPLICATIONS) {
				return enabledItems.filter((item) => item.type === ItemType.APPLICATION);
			}
			if (store.searchTab === SearchTab.ACTIONS) {
				return enabledItems.filter((item) =>
					[
						ItemType.CONFIGURATION,
						ItemType.CUSTOM,
						ItemType.USER_SCRIPT,
						ItemType.PREFERENCE_PANE,
						ItemType.TEMPORARY_RESULT,
					].includes(item.type),
				);
			}

			return enabledItems;
		},
		get currentItem(): Item | undefined {
			return store.searchItems[store.selectedIndex];
		},
		get filteredHistory(): string[] {
			const entries = [...store.history].reverse();
			const filter = store.query.trim().toLowerCase();
			if (!filter) return entries;
			return entries.filter((entry) => entry.toLowerCase().includes(filter));
		},
		//                _   _
		//      /\       | | (_)
		//     /  \   ___| |_ _  ___  _ __  ___
		//    / /\ \ / __| __| |/ _ \| '_ \/ __|
		//   / ____ \ (__| |_| | (_) | | | \__ \
		//  /_/    \_\___|\__|_|\___/|_| |_|___/
		setHoveredEventId: (id: string | null) => {
			store.hoveredEventId = id;
		},
		setHyperKeyEnabled: (enabled: boolean) => {
			store.hyperKeyEnabled = enabled;
			solNative.setHyperKeyEnabled(enabled);
		},
		rotateScratchPadColor: () => {
			if (store.scratchPadColor === ScratchPadColor.SYSTEM) {
				store.scratchPadColor = ScratchPadColor.BLUE;
			} else if (store.scratchPadColor === ScratchPadColor.BLUE) {
				store.scratchPadColor = ScratchPadColor.ORANGE;
			} else {
				store.scratchPadColor = ScratchPadColor.SYSTEM;
			}
		},
		setShowUpcomingEvent: (v: boolean) => {
			store.showUpcomingEvent = v;
			solNative.setUpcomingEventEnabled(v && store.calendarEnabled);
		},
		recordItemSelection: (item: Item) => {
			const previousCount = getSelectionCount(item);
			store.frequencies[item.id] = previousCount + 1;
			store.selectionTimestamps[item.id] = Date.now();
		},
		showEmojiPicker: () => {
			store.query = "";
			if (store.focusedWidget === Widget.EMOJIS) {
				store.focusedWidget = Widget.SEARCH;
			} else {
				store.focusWidget(Widget.EMOJIS);
			}
		},
		showSettings: (section: SettingsSection = "GENERAL") => {
			store.setQuery("");
			store.settingsSection = section;
			store.focusWidget(Widget.SETTINGS);
		},
		setSettingsSection: (section: SettingsSection) => {
			store.settingsSection = section;
		},
		saveDailymotionStream: (name: string, url: string) => {
			const videoID = extractDailymotionVideoID(url);
			if (!videoID) return false;
			const stream: DailymotionStream = {
				id: videoID,
				name: name.trim() || `Dailymotion ${videoID}`,
				url: url.trim(),
			};
			const existingIndex = store.dailymotionStreams.findIndex(
				(candidate) => candidate.id === videoID,
			);
			if (existingIndex >= 0) {
				store.dailymotionStreams[existingIndex] = stream;
			} else {
				store.dailymotionStreams.push(stream);
			}
			return true;
		},
		removeDailymotionStream: (id: string) => {
			store.dailymotionStreams = store.dailymotionStreams.filter(
				(stream) => stream.id !== id,
			);
		},
		setSelectedIndex: (idx: number) => {
			store.selectedIndex = idx;
		},
		setSearchTab: (tab: SearchTab) => {
			if (store.searchTab === tab) return;
			fileSearchRequestId += 1;
			store.searchTab = tab;
			store.selectedIndex = 0;
			store.indexedFileResults = [];
			store.isLoading = false;
			if (tab !== SearchTab.FILES && store.query) {
				store.setQuery(store.query);
			}
		},
		cycleSearchTab: (direction: 1 | -1) => {
			const currentIndex = SEARCH_TAB_ORDER.indexOf(store.searchTab);
			const nextIndex =
				(currentIndex + direction + SEARCH_TAB_ORDER.length) %
				SEARCH_TAB_ORDER.length;
			store.setSearchTab(SEARCH_TAB_ORDER[nextIndex]);
		},
		setNote: (note: string) => {
			store.note = note;
		},
		createCustomItem: (item: Item) => {
			store.customItems.push(item);
		},
		updateCustomItem: (updatedItem: Item) => {
			const index = store.customItems.findIndex((i) => i.id === updatedItem.id);
			if (index !== -1) {
				store.customItems[index] = updatedItem;
				minisearch.discard(updatedItem.id);
			}
		},
		deleteCustomItem: (itemId: string) => {
			store.customItems = store.customItems.filter((i) => i.id !== itemId);
			if (minisearch.has(itemId)) {
				minisearch.discard(itemId);
			}
		},
		setEditingCustomItem: (item: Item | null) => {
			store.editingCustomItem = item;
		},
		disableItem: (itemId: string) => {
			if (!store.disabledItemIds.includes(itemId)) {
				store.disabledItemIds.push(itemId);
				// Remove shortcut if present
				if (store.shortcuts[itemId]) {
					delete store.shortcuts[itemId];
				}
			}
		},
		enableItem: (itemId: string) => {
			store.disabledItemIds = store.disabledItemIds.filter(
				(id) => id !== itemId,
			);
		},
		isItemDisabled: (itemId: string) => {
			return store.disabledItemIds.includes(itemId);
		},
		translateQuery: async () => {
			store.isLoading = true;
			store.translationResults = [];
			store.focusedWidget = Widget.TRANSLATION;
			store.selectedIndex = 0;

			try {
				const translations = await googleTranslate(
					store.firstTranslationLanguage,
					store.secondTranslationLanguage,
					store.thirdTranslationLanguage,
					store.query,
				);

				runInAction(() => {
					store.translationResults = translations;
					store.isLoading = false;
				});
			} catch (_) {
				runInAction(() => {
					store.isLoading = false;
				});
			}
		},
		openKeyboardSettings: () => {
			try {
				Linking.openURL(`/System/Library/PreferencePanes/Keyboard.prefPane`);
			} catch (e) {
				console.error(`Could not open keyboard preferences ${e}`);
			}
		},
		setFirstTranslationLanguage: (l: string) => {
			store.firstTranslationLanguage = l;
		},
		setSecondTranslationLanguage: (l: string) => {
			store.secondTranslationLanguage = l;
		},
		setThirdTranslationLanguage: (l: string) => {
			store.thirdTranslationLanguage = l;
		},
		setOnboardingStep: (step: OnboardingStep) => {
			store.onboardingStep = step;
		},
		setGlobalShortcut: (key: "command" | "option" | "control") => {
			solNative.setGlobalShortcut(key);
			store.globalShortcut = key;
		},
		setShowWindowOn: (on: "screenWithFrontmost" | "screenWithCursor") => {
			solNative.setShowWindowOn(on);
			store.showWindowOn = on;
		},
		setGlassAppearance: (patch: Partial<GlassAppearance>) => {
			const nextAppearance = normalizeGlassAppearance({
				...toJS(store.glassAppearance),
				...patch,
			});
			store.glassAppearance = nextAppearance;
			solNative.setGlassAppearance(toJS(nextAppearance));
		},
		resetGlassAppearance: () => {
			store.glassAppearance = { ...DEFAULT_GLASS_APPEARANCE };
			solNative.setGlassAppearance(toJS(store.glassAppearance));
		},
		focusWidget: (widget: Widget) => {
			if (store.searchTab === SearchTab.FILES && widget !== Widget.SEARCH) {
				fileSearchRequestId += 1;
				store.indexedFileResults = [];
				store.isLoading = false;
			}
			store.selectedIndex = 0;
			store.focusedWidget = widget;
		},
		openAIHistory: () => {
			store.aiHistoryReturnWidget =
				store.focusedWidget === Widget.AI_CHAT ||
				store.focusedWidget === Widget.AI_ONE_SHOT
					? store.focusedWidget
					: Widget.SEARCH;
			store.focusWidget(Widget.AI_HISTORY);
		},
		closeAIHistory: () => {
			store.focusWidget(store.aiHistoryReturnWidget);
		},
		setFocus: (widget: Widget) => {
			store.focusedWidget = widget;
		},
		setQuery: (query: string) => {
			store.query = query.replace("\n", " ");
			store.selectedIndex = 0;
			store.temporaryResult = null;
			if (
				store.focusedWidget === Widget.FILE_SEARCH ||
				(store.focusedWidget === Widget.SEARCH &&
					store.searchTab === SearchTab.FILES)
			) {
				fileSearchRequestId += 1;
				store.indexedFileResults = [];
				store.isLoading = false;
			}

			if (store.query === "") {
				return;
			}

			if (
				store.focusedWidget === Widget.SEARCH &&
				store.searchTab !== SearchTab.FILES
			) {
				if (store.query.trim().toLowerCase() === "ip") {
					const querySnapshot = store.query;
					store.temporaryResult = createTextTemporaryResult(
						"Fetching…",
						"Public IP",
						{ canCopy: false, actionLabel: "Loading" },
					);
					void fetchPublicIPAddress()
						.then((ip) => {
							if (
								store.focusedWidget === Widget.SEARCH &&
								store.query === querySnapshot
							) {
								runInAction(() => {
									store.temporaryResult = createTextTemporaryResult(
										ip,
										"Public IP",
										{ copyValue: ip },
									);
								});
							}
						})
						.catch((error) => {
							console.log("Public IP request failed", error);
							if (
								store.focusedWidget === Widget.SEARCH &&
								store.query === querySnapshot
							) {
								runInAction(() => {
									store.temporaryResult = createTextTemporaryResult(
										"Unavailable",
										"Public IP",
										{ canCopy: false, actionLabel: "Unavailable" },
									);
								});
							}
						});
					return;
				}

				const timezoneResult = parseTimezoneConversion(store.query);
				if (timezoneResult != null) {
					store.temporaryResult = timezoneResult;
					return;
				}

				const unitResult = parseUnitConversion(store.query);
				if (unitResult != null) {
					store.temporaryResult = unitResult;
					return;
				}

				const flightIdentifier = parseFlightIdentifier(store.query);
				if (flightIdentifier != null) {
					const querySnapshot = store.query;
					void fetchFlightInfoFromWeb(flightIdentifier)
						.then((result) => {
							if (
								result != null &&
								store.focusedWidget === Widget.SEARCH &&
								store.query === querySnapshot
							) {
								runInAction(() => {
									store.temporaryResult = result;
								});
							}
						})
						.catch((error) => {
							console.log(
								`Flight info request failed for ${flightIdentifier}`,
								error,
							);
						});
				}

				try {
					const res = exprParser.evaluate(
						store.query,
						CALCULATOR_CONSTANT_VALUES,
					);
					if (typeof res === "number" && !Number.isNaN(res)) {
						store.temporaryResult = createTextTemporaryResult(
							formatExpressionResult(res),
							store.query,
						);
					} else {
						store.temporaryResult = null;
					}
				} catch (_) {
					store.temporaryResult = null;
				}
			}
		},
		updateApps: (
			apps: Array<{
				name: string;
				localizedName: string;
				url: string;
				isRunning: boolean;
			}>,
		) => {
			// First update the app list
			const appsRecord: Record<string, Item> = {};

			for (const { name, localizedName, url, isRunning } of apps) {
				if (name === "sol") {
					continue;
				}

				const alias = getInitials(name);
				// const plistPath = decodeURIComponent(
				//   url.replace('file://', '') + 'Contents/Info.plist',
				// )

				// if (solNative.exists(plistPath)) {
				//   try {
				//     let plistContent = solNative.readFile(plistPath)
				//     if (plistContent != null) {
				//       const properties = plist.parse(plistContent)
				//       alias = properties.CFBundleIdentifier ?? '' + getInitials(name)
				//     } else {
				//       alias = getInitials(name)
				//     }
				//   } catch (e) {
				//     // intentionally left blank
				//   }
				// }

				appsRecord[url] = {
					id: url,
					type: ItemType.APPLICATION as ItemType.APPLICATION,
					url: decodeURI(url.replace("file://", "")),
					name: name,
					localizedName: localizedName,
					isRunning,
					alias,
				};
			}

			// minisearch is stupid and there is no way to remove a single item via scanning
			// so we remove all items and add them again
			minisearch.removeAll();

			runInAction(() => {
				store.apps = Object.values(appsRecord);
			});

			// As a courtesy, we also remove keyboard shortcuts for applications that are no longer found
			// const shorcutsKeys = Object.keys(root.ui.shortcuts)
			// const ids = store.items.map(i => i.id)
			// for (const shortcutKey of shorcutsKeys) {
			//   if (!ids.includes(shortcutKey)) {
			//     delete root.ui.shortcuts[shortcutKey]
			//   }
			// }
		},
		getApps: () => {
			solNative.getApplications().then((apps) => {
				store.updateApps(apps);
			});
		},
		onShow: ({ target }: { target?: string }) => {
			store.getApps();
			store.isVisible = true;
			if (target != null) {
				switch (target) {
					case Widget.CLIPBOARD:
						store.showClipboardManager();
						return;

					case Widget.SCRATCHPAD:
						store.showScratchpad();
						return;

					case Widget.EMOJIS:
						store.showEmojiPicker();
						return;

					case Widget.SETTINGS:
						store.showSettings();
						return;
				}
				return;
			}

			// store.getApps()

			setImmediate(() => {
				if (!store.isAccessibilityTrusted) {
					store.getAccessibilityStatus();
				}

				if (!store.hasFullDiskAccess) {
					store.getFullDiskAccessStatus();
				}
			});
		},
		onHide: () => {
			fileSearchRequestId += 1;
			store.isVisible = false;
			store.focusedWidget = Widget.SEARCH;
			store.searchTab = SearchTab.ALL;
			store.indexedFileResults = [];
			store.isLoading = false;
			store.editingCustomItem = null;
			if (store.temporaryResult == null) {
				store.setQuery("");
			}
			store.selectedIndex = 0;
			store.translationResults = [];
		},
		cleanUp: () => {
			onShowListener?.remove();
			onHideListener?.remove();
			onFileSearchListener?.remove();
			onHotkeyListener?.remove();
			onAppsChangedListener?.remove();
			appareanceListener?.remove();
			bookmarksDisposer?.();
			configDisposer?.();
		},
		getCalendarAccess: () => {
			store.calendarAuthorizationStatus =
				solNative.getCalendarAuthorizationStatus();
		},
		getAccessibilityStatus: () => {
			solNative.getAccessibilityStatus().then((v) => {
				runInAction(() => {
					store.isAccessibilityTrusted = v;
				});
			});
		},
		showScratchpad: () => {
			if (store.focusedWidget === Widget.SCRATCHPAD) {
				store.focusWidget(Widget.SEARCH);
			} else {
				store.focusWidget(Widget.SCRATCHPAD);
			}
		},
		showClipboardManager: () => {
			store.query = "";
			if (store.focusedWidget === Widget.CLIPBOARD) {
				store.focusWidget(Widget.SEARCH);
			} else {
				store.focusWidget(Widget.CLIPBOARD);
			}
		},
		showProcessManager: () => {
			store.query = "";
			store.focusWidget(Widget.PROCESSES);
		},
		setCalendarEnabled: (v: boolean) => {
			store.calendarEnabled = v;
			solNative.setUpcomingEventEnabled(v && store.showUpcomingEvent);
		},
		setShowAllDayEvents: (v: boolean) => {
			store.showAllDayEvents = v;
		},
		setLaunchAtLogin: (v: boolean) => {
			store.launchAtLogin = v;
			solNative.setLaunchAtLogin(v);
		},
		getFullDiskAccessStatus: async () => {
			const hasAccess = await solNative.hasFullDiskAccess();
			runInAction(() => {
				store.hasFullDiskAccess = hasAccess;
			});
			store.getBookmarks();
		},
		getBookmarks: async () => {
			// Fetch all bookmarks and deduplicate by id
			const allBookmarks: Item[] = [];

			const safariBookmarks = await store.getSafariBookmarks();
			const braveBookmarks = await store.getBraveBookmarks();
			const chromeBookmarks = await store.getChromeBookmarks();
			const vivaldiBookmarks = await store.getVivaldiBookmarks();

			// Use a Set to keep track of unique ids
			const seenIds = new Set<string>();

			for (const bookmark of [
				...safariBookmarks,
				...braveBookmarks,
				...chromeBookmarks,
				...vivaldiBookmarks,
			]) {
				if (!seenIds.has(bookmark.id)) {
					allBookmarks.push(bookmark);
					seenIds.add(bookmark.id);
				}
			}

			runInAction(() => {
				store.bookmarks = allBookmarks;
			});
		},
		getSafariBookmarks: async (): Promise<Item[]> => {
			if (!store.hasFullDiskAccess) {
				return [];
			}
			const safariBookmarksRaw = await solNative.getSafariBookmarks();

			return safariBookmarksRaw.map((bookmark: any, idx: number): Item => {
				return {
					id: `${bookmark.title}_safari_${idx}`,
					name: bookmark.title,
					type: ItemType.BOOKMARK,
					bookmarkFolder: null,
					faviconFallback: Assets.Safari,
					url: bookmark.url,
					callback: () => {
						Linking.openURL(bookmark.url);
					},
				};
			});
		},
		getBraveBookmarks: async (): Promise<Item[]> => {
			const path = `/Users/${store.username}/Library/Application Support/BraveSoftware/Brave-Browser/Default/Bookmarks`;
			const exists = solNative.exists(path);
			if (!exists) {
				return [];
			}

			const bookmarksString = solNative.readFile(path);
			if (!bookmarksString) {
				return [];
			}

			const OGbookmarks = JSON.parse(bookmarksString);

			const bookmarks: {
				title: string;
				url: string;
				bookmarkFolder: null | string;
			}[] = [];

			traverse(bookmarks, OGbookmarks.roots.bookmark_bar.children, null);

			return bookmarks.map((bookmark, idx): Item => {
				return {
					id: `${bookmark.title}_brave_${idx}`,
					name: bookmark.title,
					bookmarkFolder: bookmark.bookmarkFolder,
					type: ItemType.BOOKMARK,
					faviconFallback: Assets.Brave,
					url: bookmark.url,
					callback: () => {
						try {
							Linking.openURL(bookmark.url);
						} catch (_) {
							// intentionally left blank
						}
					},
				};
			});
		},
		getChromeBookmarks: async (): Promise<Item[]> => {
			const username = solNative.userName();
			const path = `/Users/${username}/Library/Application Support/Google/Chrome/Default/Bookmarks`;
			const exists = solNative.exists(path);
			if (!exists) {
				return [];
			}
			const bookmarksString = solNative.readFile(path);
			if (!bookmarksString) {
				return [];
			}
			const OGbookmarks = JSON.parse(bookmarksString);

			const bookmarks: {
				title: string;
				url: string;
				bookmarkFolder: null | string;
			}[] = [];

			traverse(bookmarks, OGbookmarks.roots.bookmark_bar.children, null);

			return bookmarks.map((bookmark, idx): Item => {
				return {
					id: `${bookmark.title}_brave_${idx}`,
					name: bookmark.title,
					bookmarkFolder: bookmark.bookmarkFolder,
					type: ItemType.BOOKMARK,
					faviconFallback: Assets.Chrome,
					url: bookmark.url,
					callback: () => {
						Linking.openURL(bookmark.url);
					},
				};
			});
		},

		getVivaldiBookmarks: async (): Promise<Item[]> => {
			const username = solNative.userName();
			const path = `/Users/${username}/Library/Application Support/Vivaldi/Default/Bookmarks`;
			const exists = solNative.exists(path);
			if (!exists) {
				return [];
			}
			const bookmarksString = solNative.readFile(path);
			if (!bookmarksString) {
				return [];
			}
			const OGbookmarks = JSON.parse(bookmarksString);

			const bookmarks: {
				title: string;
				url: string;
				bookmarkFolder: null | string;
			}[] = [];

			traverse(bookmarks, OGbookmarks.roots.bookmark_bar.children, null);

			return bookmarks.map((bookmark, idx): Item => {
				return {
					id: `${bookmark.title}_vivaldi_${idx}`,
					name: bookmark.title,
					bookmarkFolder: bookmark.bookmarkFolder,
					type: ItemType.BOOKMARK,
					faviconFallback: Assets.Vivaldi,
					url: bookmark.url,
					callback: () => {
						Linking.openURL(bookmark.url);
					},
				};
			});
		},

		setMediaKeyForwardingEnabled: (enabled: boolean) => {
			store.mediaKeyForwardingEnabled = enabled;
			solNative.setMediaKeyForwardingEnabled(enabled);
		},

		setTargetHeight: (height: number) => {
			store.targetHeight = height;
		},

		onColorSchemeChange({
			colorScheme,
		}: {
			colorScheme: "light" | "dark" | null | undefined;
		}) {
			if (colorScheme === "dark") {
				store.isDarkMode = true;
				// nativeWindColorScheme.set("dark")
			} else {
				store.isDarkMode = false;
				// nativeWindColorScheme.set("light")
			}
			RNRestart.restart();
		},

		addToHistory: (query: string) => {
			if (query.trim()) store.history.push(query);
		},

		showFileSearch: () => {
			store.focusWidget(Widget.FILE_SEARCH);
			store.query = "";
		},

		addSearchFolder: (folder: string) => {
			store.searchFolders.push(folder);
			store.isIndexing = true;
			void solNative.indexPaths([folder]).then(() => {
				runInAction(() => {
					store.isIndexing = false;
				});
			});
		},

		removeSearchFolder: (folder: string) => {
			store.searchFolders = store.searchFolders.filter((f) => f !== folder);
			void solNative.removeIndexedPath(folder);
		},

		reindexAll: () => {
			solNative.clearIndex();
			if (store.searchFolders.length === 0) return;
			runInAction(() => {
				store.isIndexing = true;
			});
			void solNative.indexPaths(toJS(store.searchFolders)).then(() => {
				runInAction(() => {
					store.isIndexing = false;
				});
			});
		},

		setSearchEngine: (engine: SearchEngine) => {
			store.searchEngine = engine;
		},

		setCustomSearchUrl: (url: string) => {
			store.customSearchUrl = url;
		},

		onHotKey: async ({ id }: { id: string }) => {
			const item = [
				...store.apps,
				...baseItems,
				...store.customItems,
				...root.scripts.scripts,
				...(store.showInAppBrowserBookMarks ? store.bookmarks : []),
			].find((i) => i.id === id);

			if (item == null) {
				return;
			}

			// TODO logic repeated from keystroke.store.ts. At some point de-duplicate
			if (item.type === ItemType.CUSTOM) {
				if (!item.text) {
					return;
				}

				if (item.isApplescript) {
					solNative.executeAppleScript(item.text);
				} else {
					try {
						const canOpenURL = await Linking.canOpenURL(item.text);
						if (canOpenURL) {
							await Linking.openURL(item.text);
						} else {
							solNative.showToast(`Could not open URL: ${item.text}`, "error");
						}
					} catch (_e) {
						solNative.showToast(`Could not open URL: ${item.text}`, "error");
					}
				}
			}

			if (item.callback) {
				item.callback();
			} else if (item.url) {
				solNative.openFile(item.url);
			}

			if (itemsThatShouldShowWindow.includes(item.id)) {
				setTimeout(solNative.showWindow, 0);
			}
		},

		setShortcut(id: string, shortcut: string) {
			const normalizedShortcut = normalizeShortcut(shortcut);

			// Check for duplicate shortcut
			if (normalizedShortcut !== "") {
				const isDuplicate = Object.entries(store.shortcuts).some(
					([key, value]) => value === normalizedShortcut && key !== id,
				);
				if (isDuplicate) {
					solNative.showToast("Shortcut already exists", "error", 4);
					return;
				}
			}

			store.shortcuts[id] = normalizedShortcut;
			solNative.updateHotkeys(toJS(store.shortcuts));
		},

		restoreDefaultShorcuts() {
			store.shortcuts = defaultShortcuts;
			solNative.updateHotkeys(defaultShortcuts);
		},

		setWindowHeight(e: LayoutChangeEvent) {
			solNative.setWindowHeight(e.nativeEvent.layout.height);
		},

		setShowInAppBrowserBookmarks: (v: boolean) => {
			store.showInAppBrowserBookMarks = v;
		},

		// Old custom items are not migrated to the new format which has an id
		// This function is used to migrate the old custom items to the new format
		// by just adding a random id
		migrateCustomItems() {
			store.customItems = store.customItems.map((i) => {
				if (i.id) {
					return i;
				}

				return { ...i, id: Math.random().toString() };
			});
		},
		setHasDismissedGettingStarted: (v: boolean) => {
			store.hasDismissedGettingStarted = v;
		},
		applicationsChanged: () => {
			store.getApps();
		},
		closeKeyboardRecorder: () => {
			store.showKeyboardRecorder = false;
			store.keyboardRecorderSelectedItem = null;
			store.shortcutSearchMode = false;
		},
		setShowKeyboardRecorderForItem: (show: boolean, itemId: string) => {
			store.showKeyboardRecorder = show;
			store.keyboardRecorderSelectedItem = itemId;
			store.shortcutSearchMode = false;
		},
		startShortcutSearch: () => {
			store.showKeyboardRecorder = true;
			store.shortcutSearchMode = true;
			store.keyboardRecorderSelectedItem = null;
		},
		setShortcutSearchFilter: (shortcut: string | null) => {
			store.shortcutSearchFilter = shortcut;
		},
		clearShortcutSearch: () => {
			store.shortcutSearchFilter = null;
			store.shortcutSearchMode = false;
		},
		setShortcutFromUI: (shortcut: string[]) => {
			const normalizedShortcut = normalizeShortcut(shortcut.join("+"));

			// Check if we're in shortcut search mode
			if (store.shortcutSearchMode) {
				store.shortcutSearchFilter = normalizedShortcut;
				setTimeout(() => {
					runInAction(() => {
						store.showKeyboardRecorder = false;
						store.shortcutSearchMode = false;
					});
				}, 500);
				return;
			}

			setTimeout(() => {
				runInAction(() => {
					store.showKeyboardRecorder = false;
				});
			}, 2000);

			const itemId = store.keyboardRecorderSelectedItem;
			store.keyboardRecorderSelectedItem = null;
			if (!itemId) {
				return;
			}
			store.setShortcut(itemId, normalizedShortcut);
		},
		confirm: async (title: string, callback: () => unknown) => {
			store.confirmDialogShown = true;
			store.confirmCallback = callback;
			store.confirmTitle = title;
		},
		closeConfirm: () => {
			store.confirmDialogShown = false;
			store.confirmCallback = null;
			store.confirmTitle = null;
		},
		executeConfirmCallback: async () => {
			const callback = store.confirmCallback;
			store.closeConfirm();
			await callback?.();
		},
		reloadJsonConfig,
	});

	bookmarksDisposer = reaction(
		() => [store.showInAppBrowserBookMarks],
		() => {
			minisearch.removeAll();
		},
	);

	hydrate().then(() => {
		configDisposer = autorun(() => {
			getPersistedUISnapshot();
			persistToJson();
		});
		store.getCalendarAccess();
		store.getAccessibilityStatus();
		store.getFullDiskAccessStatus();
		solNative.setUpcomingEventEnabled(
			store.showUpcomingEvent && store.calendarEnabled,
		);

		if (store.searchFolders.length > 0) {
			if (!solNative.hasIndexedContent()) {
				runInAction(() => {
					store.isIndexing = true;
				});
				void solNative.indexPaths(toJS(store.searchFolders)).then(() => {
					runInAction(() => {
						store.isIndexing = false;
					});
				});
			} else {
				// DB already populated — just start watching for changes
				solNative.startWatchingPaths(toJS(store.searchFolders));
			}
		}
	});

	appareanceListener = Appearance.addChangeListener(store.onColorSchemeChange);
	onShowListener = solNative.addListener("onShow", store.onShow);
	onHideListener = solNative.addListener("onHide", store.onHide);
	onHotkeyListener = solNative.addListener("hotkey", store.onHotKey);
	// onAppsChangedListener = solNative.addListener(
	// 	"applicationsChanged",
	// 	store.applicationsChanged,
	// );

	return store;
};
