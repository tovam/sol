import {
	type FloatingSpreadsheetSummary,
	solNative,
} from "lib/SolNative";
import { makeAutoObservable, runInAction } from "mobx";
import type { IRootStore } from "store";
import { ItemType } from "./ui.store";

const normalizeFilter = (value: string) =>
	value
		.normalize("NFD")
		.replace(/[\u0300-\u036f]/g, "")
		.toLocaleLowerCase();

const formatUpdatedAt = (timestamp: number) => {
	try {
		return new Date(timestamp).toLocaleString(undefined, {
			dateStyle: "medium",
			timeStyle: "short",
		});
	} catch {
		return new Date(timestamp).toLocaleString();
	}
};

export type SpreadsheetsStore = ReturnType<typeof createSpreadsheetsStore>;

export const createSpreadsheetsStore = (root: IRootStore) => {
	let refreshRequest = 0;
	const store = makeAutoObservable({
		summaries: [] as FloatingSpreadsheetSummary[],
		archivedSummaries: [] as FloatingSpreadsheetSummary[],
		isLoading: false,
		isLoadingArchived: false,

		get createItem(): Item {
			return {
				id: "create_floating_spreadsheet_command",
				icon: "▦",
				name: "New Spreadsheet",
				subName: "Floating · always on top · saved automatically",
				type: ItemType.CONFIGURATION,
				callback: () => {
					void store.create();
				},
			};
		},

		itemsForFilter: (filter: string): Item[] => {
			const needle = normalizeFilter(filter);
			const summaries = needle
				? store.summaries.filter((summary) =>
						normalizeFilter(summary.name).includes(needle),
					)
				: store.summaries;
			return summaries.map((summary): Item => {
				const cells = `${summary.cellCount} cell${summary.cellCount === 1 ? "" : "s"}`;
				const charts = `${summary.chartCount} chart${summary.chartCount === 1 ? "" : "s"}`;
				return {
					id: `floating_spreadsheet_${summary.id}`,
					icon: "▦",
					name: summary.name,
					subName: `${formatUpdatedAt(summary.updatedAt)} · ${cells} · ${charts} · Enter open · ⌘Enter delete`,
					type: ItemType.CONFIGURATION,
					preventClose: true,
					callback: () => {
						void store.open(summary.id);
					},
					metaCallback: () => {
						root.ui.confirm(`Delete “${summary.name}”?`, () => {
							void store.delete(summary.id);
						});
					},
				};
			});
		},

		refresh: async () => {
			const request = ++refreshRequest;
			runInAction(() => {
				store.isLoading = true;
			});
			try {
				const summaries = await solNative.getFloatingSpreadsheets();
				if (request !== refreshRequest) return;
				runInAction(() => {
					store.summaries = summaries;
					store.isLoading = false;
				});
				root.ui.invalidateSearchIndex();
			} catch {
				if (request !== refreshRequest) return;
				runInAction(() => {
					store.isLoading = false;
				});
			}
		},

		refreshArchived: async () => {
			runInAction(() => {
				store.isLoadingArchived = true;
			});
			try {
				const summaries = await solNative.getArchivedFloatingSpreadsheets();
				runInAction(() => {
					store.archivedSummaries = summaries;
					store.isLoadingArchived = false;
				});
			} catch {
				runInAction(() => {
					store.isLoadingArchived = false;
				});
			}
		},

		create: async () => {
			try {
				await solNative.createFloatingSpreadsheet();
				void store.refresh();
			} catch (error) {
				void solNative.showToast(
					`Could not create spreadsheet: ${String(error)}`,
					"error",
				);
			}
		},

		open: async (identifier: string) => {
			solNative.hideWindow();
			try {
				await solNative.reopenFloatingSpreadsheet(identifier);
				void store.refresh();
			} catch (error) {
				void solNative.showToast(
					`Could not open spreadsheet: ${String(error)}`,
					"error",
				);
			}
		},

		restore: async (identifier: string) => {
			solNative.hideWindow();
			try {
				await solNative.restoreArchivedFloatingSpreadsheet(identifier);
				await Promise.all([store.refresh(), store.refreshArchived()]);
			} catch (error) {
				void solNative.showToast(
					`Could not restore spreadsheet: ${String(error)}`,
					"error",
				);
			}
		},

		rename: async (identifier: string, name: string) => {
			try {
				await solNative.renameFloatingSpreadsheet(identifier, name);
				await store.refresh();
			} catch (error) {
				void solNative.showToast(
					`Could not rename spreadsheet: ${String(error)}`,
					"error",
				);
			}
		},

		archive: async (identifier: string) => {
			try {
				await solNative.archiveFloatingSpreadsheet(identifier);
				await Promise.all([store.refresh(), store.refreshArchived()]);
			} catch (error) {
				void solNative.showToast(
					`Could not archive spreadsheet: ${String(error)}`,
					"error",
				);
			}
		},

		delete: async (identifier: string) => {
			try {
				await solNative.deleteFloatingSpreadsheet(identifier);
				await Promise.all([store.refresh(), store.refreshArchived()]);
			} catch (error) {
				void solNative.showToast(
					`Could not delete spreadsheet: ${String(error)}`,
					"error",
				);
			}
		},

		cleanUp: () => {
			refreshRequest += 1;
		},
	});

	void store.refresh();
	return store;
};
