import {
	fetchCurrencyRates,
	normalizeCurrencyRateSnapshot,
	type CurrencyRateSnapshot,
} from "lib/currencyRates";
import {
	makeAutoObservable,
	reaction,
	runInAction,
	type IReactionDisposer,
} from "mobx";
import type { IRootStore } from "store";
import {
	readPersistedRuntimeStore,
	writePersistedStore,
} from "./persisted-config";

type PersistedCurrencyRateState = {
	snapshot?: CurrencyRateSnapshot | null;
};

export type CurrencyRatesStore = ReturnType<typeof createCurrencyRatesStore>;

export const createCurrencyRatesStore = (root: IRootStore) => {
	let refreshTimer: ReturnType<typeof setInterval> | undefined;
	let refreshPromise: Promise<CurrencyRateSnapshot | null> | null = null;
	let scheduleDisposer: IReactionDisposer | undefined;
	const persisted = readPersistedRuntimeStore<PersistedCurrencyRateState>(
		"currencyRates",
	);

	const clearRefreshTimer = () => {
		if (refreshTimer) {
			clearInterval(refreshTimer);
			refreshTimer = undefined;
		}
	};

	const store = makeAutoObservable({
		snapshot: normalizeCurrencyRateSnapshot(persisted?.snapshot),
		isRefreshing: false,
		lastError: null as string | null,

		refresh: (): Promise<CurrencyRateSnapshot | null> => {
			if (refreshPromise) return refreshPromise;
			runInAction(() => {
				store.isRefreshing = true;
				store.lastError = null;
			});

			refreshPromise = fetchCurrencyRates()
				.then((snapshot) => {
					runInAction(() => {
						store.snapshot = snapshot;
						store.isRefreshing = false;
					});
					writePersistedStore("currencyRates", { snapshot });
					return snapshot;
				})
				.catch((error) => {
					runInAction(() => {
						store.isRefreshing = false;
						store.lastError =
							error instanceof Error ? error.message : "Could not refresh rates";
					});
					return null;
				})
				.finally(() => {
					refreshPromise = null;
				});
			return refreshPromise;
		},

		ensureSnapshot: async (): Promise<CurrencyRateSnapshot | null> => {
			if (store.snapshot) return store.snapshot;
			return store.refresh();
		},

		cleanUp: () => {
			clearRefreshTimer();
			scheduleDisposer?.();
		},
	});

	scheduleDisposer = reaction(
		() => [
			root.ui.initialHydrationComplete,
			root.ui.currencyRefreshIntervalMinutes,
		] as const,
		([isReady, intervalMinutes]) => {
			clearRefreshTimer();
			if (!isReady) return;
			void store.refresh();
			refreshTimer = setInterval(
				() => void store.refresh(),
				intervalMinutes * 60_000,
			);
		},
		{ fireImmediately: true },
	);

	return store;
};
