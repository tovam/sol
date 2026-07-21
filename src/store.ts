import { createContext, useContext } from "react";
import { type AIStore, createAIStore } from "stores/ai.store";
import { type CalendarStore, createCalendarStore } from "stores/calendar.store";
import {
	type ClipboardStore,
	createClipboardStore,
} from "stores/clipboard.store";
import { createEmojiStore, type EmojiStore } from "stores/emoji.store";
import {
	createKeystrokeStore,
	type KeystrokeStore,
} from "stores/keystroke.store";
import {
	createProcessesStore,
	type ProcessesStore,
} from "stores/processes.store";
import { createScriptsStore, type ScriptsStore } from "stores/scripts.store";
import { createTimerStore, type TimerStore } from "stores/timer.store";
import { createUIStore, type UIStore } from "./stores/ui.store";

export interface IRootStore {
	ai: AIStore;
	ui: UIStore;
	clipboard: ClipboardStore;
	keystroke: KeystrokeStore;
	calendar: CalendarStore;
	processes: ProcessesStore;
	emoji: EmojiStore;
	scripts: ScriptsStore;
	timer: TimerStore;
	cleanUp: () => void;
}

const createRootStore = (): IRootStore => {
	const store: any = {};

	store.ai = createAIStore();
	store.ui = createUIStore(store);
	store.clipboard = createClipboardStore(store);
	store.keystroke = createKeystrokeStore(store);
	store.calendar = createCalendarStore(store);
	store.processes = createProcessesStore(store);
	store.scripts = createScriptsStore(store);
	store.emoji = createEmojiStore(store);
	store.timer = createTimerStore();
	(store as IRootStore).cleanUp = () => {
		store.ai.cleanUp();
		store.ui.cleanUp();
		store.calendar.cleanUp();
		store.keystroke.cleanUp();
		store.clipboard.cleanUp();
		store.scripts.cleanUp();
		store.timer.cleanUp();
	};

	return store;
};

export const root = createRootStore();

// @ts-expect-error hot is RN
module.hot?.dispose(() => {
	root.cleanUp();
});

export const StoreContext = createContext<IRootStore>(root);
export const StoreProvider = StoreContext.Provider;
export const useStore = () => useContext(StoreContext);
