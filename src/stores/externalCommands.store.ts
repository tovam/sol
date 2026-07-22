import {
	type ExternalCommandProvider,
	solNative,
} from "lib/SolNative";
import { makeAutoObservable, reaction, runInAction } from "mobx";
import type { EmitterSubscription } from "react-native";
import type { IRootStore } from "store";
import { ItemType } from "./ui.store";

let providersChangedListener: EmitterSubscription | undefined;
let reservedCommandsDisposer: (() => void) | undefined;

const builtInCommandNames = ["ai", "ia", "dm"];

export type ExternalCommandsStore = ReturnType<
	typeof createExternalCommandsStore
>;

export const createExternalCommandsStore = (root: IRootStore) => {
	const reservedCommandNames = () =>
		new Set(
			[
				...builtInCommandNames,
				...root.scripts.scripts.flatMap((script) =>
					script.command ? [script.command] : [],
				),
				...root.ui.dailymotionStreams.flatMap((stream) =>
					stream.command ? [stream.command] : [],
				),
			].map((name) => name.toLowerCase()),
		);

	const store = makeAutoObservable({
		providers: [] as ExternalCommandProvider[],

		get items(): Item[] {
			const reserved = reservedCommandNames();
			return store.providers
				.filter((provider) => provider.state === "active")
				.flatMap((provider) =>
					provider.commands
						.filter((command) => !reserved.has(command.name.toLowerCase()))
						.map((command): Item => {
							const iconIsSymbol = command.icon?.type === "sf-symbol";
							const icon =
								command.icon?.type === "emoji" ? command.icon.value : "⌘";
							return {
								id: `external-command:${provider.providerId}:${command.name}`,
								name: command.label,
								icon,
								...(iconIsSymbol && command.symbolImageDataURL
									? {
											iconImage: { uri: command.symbolImageDataURL },
											iconTint: true,
										}
									: {}),
								type: ItemType.EXTERNAL_COMMAND,
								subName: [command.name, command.detail, provider.provider.name]
									.filter(Boolean)
									.join(" · "),
								command: command.name,
								commandDetail: command.detail,
								commandSource: provider.provider.name,
								commandArgumentMode: command.argumentMode,
								callback: () => {
									void store.execute(
										provider.providerId,
										command.name,
										"",
										[],
									);
								},
								commandCallback: (arguments_: string[], rawArgument: string) => {
									void store.execute(
										provider.providerId,
										command.name,
										rawArgument,
										arguments_,
									);
								},
							};
						}),
				);
		},

		loadProviders: async () => {
			try {
				const providers = await solNative.getExternalCommandProviders();
				runInAction(() => {
					store.providers = providers;
				});
				root.ui.invalidateSearchIndex();
			} catch {
				void solNative.showToast(
					"Could not load external command providers",
					"error",
				);
			}
		},

		execute: async (
			providerId: string,
			commandName: string,
			raw: string,
			arguments_: string[],
		) => {
			try {
				const accepted = await solNative.invokeExternalCommand(
					providerId,
					commandName,
					raw,
					arguments_,
				);
				if (!accepted) {
					void solNative.showToast(
						"The external command provider is no longer available",
						"error",
					);
					void store.loadProviders();
				}
			} catch {
				void solNative.showToast(
					"Could not invoke the external command provider",
					"error",
				);
			}
		},

		cleanUp: () => {
			providersChangedListener?.remove();
			providersChangedListener = undefined;
			reservedCommandsDisposer?.();
			reservedCommandsDisposer = undefined;
		},
	});

	providersChangedListener = solNative.addListener(
		"externalCommandProvidersChanged",
		() => {
			void store.loadProviders();
		},
	);

	reservedCommandsDisposer = reaction(
		() => [
			root.scripts.scripts
				.flatMap((script) => (script.command ? [script.command] : []))
				.sort()
				.join("\u0000"),
			root.ui.dailymotionStreams
				.flatMap((stream) => (stream.command ? [stream.command] : []))
				.sort()
				.join("\u0000"),
		],
		() => {
			solNative.setExternalCommandReservedNames([...reservedCommandNames()]);
			root.ui.invalidateSearchIndex();
		},
		{ fireImmediately: true },
	);

	void store.loadProviders();
	return store;
};
