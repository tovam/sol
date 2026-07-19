import { fetchPublicIPAddress } from "lib/publicIp";
import { solNative } from "lib/SolNative";
import { useEffect, useState } from "react";
import { ActivityIndicator, Text, TouchableOpacity, View } from "react-native";

type NativeNetworkInfo = {
	connection?: string;
	ssid?: string;
	interface?: string;
	localIp?: string;
	gateway?: string;
	dns?: string[];
	hostname?: string;
};

type NetworkInfo = NativeNetworkInfo & {
	publicIp?: string;
};

export function isNetworkQuery(query: string): boolean {
	const normalized = query.trim().toLowerCase();
	return normalized.length >= 3 && "network".startsWith(normalized);
}

function InfoRow({ label, value }: { label: string; value?: string }) {
	return (
		<View className="gap-0.5">
			<Text className="text-[10px] uppercase tracking-wide darker-text">
				{label}
			</Text>
			<Text className="text-xs font-medium" numberOfLines={2} selectable>
				{value || "—"}
			</Text>
		</View>
	);
}

export function NetworkPanel() {
	const [info, setInfo] = useState<NetworkInfo>({});
	const [loading, setLoading] = useState(true);
	const [refreshToken, setRefreshToken] = useState(0);

	// biome-ignore lint/correctness/useExhaustiveDependencies: refreshToken intentionally triggers a fresh network snapshot.
	useEffect(() => {
		let active = true;
		setLoading(true);

		void Promise.allSettled([
			solNative.getNetworkInfo(),
			fetchPublicIPAddress(),
		]).then(([nativeResult, publicResult]) => {
			if (!active) return;
			setInfo({
				...(nativeResult.status === "fulfilled" ? nativeResult.value : {}),
				publicIp:
					publicResult.status === "fulfilled" ? publicResult.value : undefined,
			});
			setLoading(false);
		});

		return () => {
			active = false;
		};
	}, [refreshToken]);

	return (
		<View className="w-[30%] border-l border-color px-4 py-3 gap-3 subBg">
			<View className="flex-row items-center justify-between">
				<View>
					<Text className="text-sm font-semibold">Network</Text>
					<Text className="text-[10px] darker-text">
						{info.connection || "Current connection"}
					</Text>
				</View>
				{loading ? (
					<ActivityIndicator size="small" />
				) : (
					<TouchableOpacity
						onPress={() => setRefreshToken((value) => value + 1)}
						className="rounded-md px-2 py-1 bg-neutral-200 dark:bg-neutral-700"
					>
						<Text className="text-[10px]">Refresh</Text>
					</TouchableOpacity>
				)}
			</View>

			<InfoRow label="Wi-Fi" value={info.ssid} />
			<InfoRow label="Public IP" value={info.publicIp} />
			<InfoRow label="Local IP" value={info.localIp} />
			<InfoRow label="Interface" value={info.interface} />
			<InfoRow label="Gateway" value={info.gateway} />
			<InfoRow label="DNS" value={info.dns?.join(", ")} />
			<InfoRow label="Hostname" value={info.hostname} />
		</View>
	);
}
