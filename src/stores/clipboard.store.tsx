import { captureException } from "@sentry/react-native";
import { solNative } from "lib/SolNative";
import MiniSearch from "minisearch";
import { makeAutoObservable } from "mobx";
import type { EmitterSubscription } from "react-native";
import type { IRootStore } from "store";
import { replacePersistedStore } from "./persisted-config";
import { Widget } from "./ui.store";

const MAX_ITEMS = 1000;
const MANAGED_PASTEBOARD_IMAGES_PATH = `/Users/${solNative.userName()}/.config/sol/images_pasteboard`;

let onTextCopiedListener: EmitterSubscription | undefined;
let onFileCopiedListener: EmitterSubscription | undefined;

export type ClipboardStore = ReturnType<typeof createClipboardStore>;

export type PasteItem = {
	id: number;
	text: string;
	url?: string | null;
	bundle?: string | null;
	datetime: number; // Unix timestamp when copied
};

const minisearch = new MiniSearch({
	fields: ["text"],
	storeFields: ["id", "text", "url", "bundle", "datetime"],
	// tokenize: (text: string, fieldName?: string) =>
	// 	text.toLowerCase().split(/[\s\.-]+/),
});

function isManagedPasteboardImagePath(path: string | null | undefined) {
	return !!path && path.startsWith(`${MANAGED_PASTEBOARD_IMAGES_PATH}/`);
}

function removeManagedImageFile(item: PasteItem | undefined) {
	if (!item?.url || !isManagedPasteboardImagePath(item.url)) {
		return;
	}

	try {
		if (solNative.exists(item.url)) {
			solNative.del(item.url);
		}
	} catch (e) {
		captureException(e);
	}
}

function cleanupOrphanedManagedImageFiles(items: PasteItem[]) {
	try {
		if (!solNative.exists(MANAGED_PASTEBOARD_IMAGES_PATH)) {
			return;
		}

		const referencedPaths = new Set(
			items
				.map((item) => item.url)
				.filter((path): path is string => isManagedPasteboardImagePath(path)),
		);

		const files = solNative.ls(MANAGED_PASTEBOARD_IMAGES_PATH);
		for (const fileName of files) {
			const fullPath = `${MANAGED_PASTEBOARD_IMAGES_PATH}/${fileName}`;
			if (!referencedPaths.has(fullPath) && solNative.exists(fullPath)) {
				solNative.del(fullPath);
			}
		}
	} catch (e) {
		captureException(e);
	}
}

export const createClipboardStore = (root: IRootStore) => {
	const store = makeAutoObservable({
		deleteItem: (index: number) => {
			if (index >= 0 && index < store.items.length) {
				removeManagedImageFile(store.items[index]);
				minisearch.remove(store.items[index]);
				store.items.splice(index, 1);
			}
		},
		deleteAllItems: () => {
			store.items.forEach(removeManagedImageFile);
			store.items = [];
			minisearch.removeAll();
		},
		items: [] as PasteItem[],
		onFileCopied: (obj: {
			text: string;
			url: string;
			bundle: string | null;
		}) => {
			const newItem: PasteItem = {
				id: +Date.now(),
				datetime: Date.now(),
				...obj,
			};

			// const index = store.items.findIndex(t => t.text === newItem.text)
			// // Item already exists, move to top
			// if (index !== -1) {
			//   // Re-add to minisearch to update the order
			//   minisearch.remove(store.items[index])
			//   minisearch.add(newItem)

			//   store.popToTop(index)
			//   return
			// }

			// Item does not already exist, put to queue and add to minisearch
			store.items.unshift(newItem);
			minisearch.add(newItem);

			// Remove last item from minisearch
			store.removeLastItemIfNeeded();
		},
		onTextCopied: (obj: { text: string; bundle: string | null }) => {
			if (!obj.text) {
				return;
			}

			const newItem: PasteItem = {
				id: Date.now().valueOf(),
				datetime: Date.now(),
				...obj,
			};

			const index = store.items.findIndex((t) => t.text === newItem.text);
			// Item already exists, move to top
			if (index !== -1) {
				// Re-add to minisearch to update the order
				minisearch.remove(store.items[index]);
				minisearch.add(store.items[index]);

				store.popToTop(index);
				return;
			}

			// Item does not already exist, put to queue and add to minisearch
			store.items.unshift(newItem);
			minisearch.add(newItem);

			// Remove last item from minisearch
			store.removeLastItemIfNeeded();
		},
		get clipboardItems(): PasteItem[] {
			const items = store.items;

			if (!root.ui.query || root.ui.focusedWidget !== Widget.CLIPBOARD) {
				return items;
			}

			// Boost recent items in search results
			const now = Date.now();
			return minisearch.search(root.ui.query, {
				boostDocument: (_, __, storedFields) => {
					const dt =
						typeof storedFields?.datetime === "number"
							? storedFields.datetime
							: Number(storedFields?.datetime);
					if (!dt || Number.isNaN(dt)) return 1;
					// Boost items copied in the last 24h, scale down for older
					const hoursAgo = (now - dt) / (1000 * 60 * 60);
					if (hoursAgo < 1) return 1.2; // very recent
					if (hoursAgo < 24) return 1.1; // recent
					return 1;
				},
				// boost: { text: 2 },
				// prefix: true,
				// fuzzy: 0.1,
			}) as any;
		},
		removeLastItemIfNeeded: () => {
			if (store.items.length > MAX_ITEMS) {
				const removedItem = store.items[store.items.length - 1];
				removeManagedImageFile(removedItem);

				try {
					minisearch.remove(store.items[store.items.length - 1]);
				} catch (e) {
					captureException(e);
				}

				store.items = store.items.slice(0, MAX_ITEMS);
			}
		},
		popToTop: (index: number) => {
			const newItems = [...store.items];
			const item = newItems.splice(index, 1);
			newItems.unshift(item[0]);
			store.items = newItems;
		},
		cleanUp: () => {
			onTextCopiedListener?.remove();
			onTextCopiedListener = undefined;
			onFileCopiedListener?.remove();
			onFileCopiedListener = undefined;
			store.deleteAllItems();
			cleanupOrphanedManagedImageFiles([]);
		},
	});

	cleanupOrphanedManagedImageFiles([]);

	onTextCopiedListener = solNative.addListener(
		"onTextCopied",
		store.onTextCopied,
	);
	onFileCopiedListener = solNative.addListener(
		"onFileCopied",
		store.onFileCopied,
	);

	const purgePersistentHistory = () => {
		if (!replacePersistedStore("clipboard", { historyPurged: true })) {
			console.warn("Could not purge persisted clipboard history");
		}
	};

	purgePersistentHistory();

	return store;
};
