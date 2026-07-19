import { solNative } from "lib/SolNative";
import { makeAutoObservable } from "mobx";

export type TimerStatus = "idle" | "running" | "paused" | "finished";
export type TimerStore = ReturnType<typeof createTimerStore>;

export function parseTimerDuration(input: string): number | null {
	const normalized = input
		.trim()
		.toLowerCase()
		.replace(/^(?:timer|countdown|minuteur)\s+/, "");
	if (/^\d+(?:\.\d+)?$/.test(normalized)) {
		const minutes = Number(normalized);
		return minutes > 0 ? Math.round(minutes * 60) : null;
	}

	const tokenPattern =
		/(\d+(?:\.\d+)?)\s*(hours?|hrs?|h|minutes?|mins?|m|seconds?|secs?|s)/gy;
	let offset = 0;
	let totalSeconds = 0;
	let foundToken = false;

	while (offset < normalized.length) {
		while (normalized[offset] === " ") offset += 1;
		if (offset >= normalized.length) break;
		tokenPattern.lastIndex = offset;
		const match = tokenPattern.exec(normalized);
		if (!match) return null;

		const value = Number(match[1]);
		const unit = match[2];
		if (unit.startsWith("h")) totalSeconds += value * 3_600;
		else if (unit.startsWith("m")) totalSeconds += value * 60;
		else totalSeconds += value;
		foundToken = true;
		offset = tokenPattern.lastIndex;
	}

	return foundToken && totalSeconds > 0 ? Math.round(totalSeconds) : null;
}

export function formatTimerDuration(totalSeconds: number) {
	const seconds = Math.max(0, Math.ceil(totalSeconds));
	const hours = Math.floor(seconds / 3_600);
	const minutes = Math.floor((seconds % 3_600) / 60);
	const remainder = seconds % 60;
	return hours > 0
		? `${hours.toString().padStart(2, "0")}:${minutes.toString().padStart(2, "0")}:${remainder.toString().padStart(2, "0")}`
		: `${minutes.toString().padStart(2, "0")}:${remainder.toString().padStart(2, "0")}`;
}

export const createTimerStore = () => {
	let interval: ReturnType<typeof setInterval> | null = null;
	let endAt = 0;

	const stopInterval = () => {
		if (interval != null) clearInterval(interval);
		interval = null;
	};

	const store = makeAutoObservable({
		durationSeconds: 300,
		remainingSeconds: 300,
		status: "idle" as TimerStatus,

		setDuration: (seconds: number) => {
			const safeSeconds = Math.max(1, Math.round(seconds));
			store.durationSeconds = safeSeconds;
			if (store.status !== "running" && store.status !== "paused") {
				store.remainingSeconds = safeSeconds;
			}
		},

		start: (seconds = store.durationSeconds) => {
			stopInterval();
			solNative.prepareTimerNotifications();
			store.durationSeconds = Math.max(1, Math.round(seconds));
			store.remainingSeconds = store.durationSeconds;
			store.status = "running";
			endAt = Date.now() + store.durationSeconds * 1_000;
			interval = setInterval(store.tick, 250);
		},

		pause: () => {
			if (store.status !== "running") return;
			store.tick();
			stopInterval();
			store.status = "paused";
		},

		resume: () => {
			if (store.status !== "paused" || store.remainingSeconds <= 0) return;
			store.status = "running";
			endAt = Date.now() + store.remainingSeconds * 1_000;
			interval = setInterval(store.tick, 250);
		},

		cancel: () => {
			stopInterval();
			store.status = "idle";
			store.remainingSeconds = store.durationSeconds;
		},

		tick: () => {
			if (store.status !== "running") return;
			store.remainingSeconds = Math.max(0, (endAt - Date.now()) / 1_000);
			if (store.remainingSeconds > 0) return;

			stopInterval();
			store.status = "finished";
			void solNative.showToast("Timer finished", "success", 10);
			solNative.notifyTimerFinished();
		},

		cleanUp: stopInterval,
	});

	return store;
};
