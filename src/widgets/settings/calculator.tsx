import clsx from "clsx";
import { Input } from "components/Input";
import { MySwitch } from "components/MySwitch";
import { DEFAULT_CURRENCY_REFRESH_INTERVAL_MINUTES, MAX_CURRENCY_REFRESH_INTERVAL_MINUTES, MIN_CURRENCY_REFRESH_INTERVAL_MINUTES } from "lib/currencyRates";
import { observer } from "mobx-react-lite";
import { useEffect, useState } from "react";
import { ScrollView, Text, TouchableOpacity, View } from "react-native";
import { useStore } from "store";
import { expandCalculatorVariables, isCalculatorExpressionCandidate, validateCalculatorVariableName } from "lib/unitExpression";

const VariableSettings = observer(() => {
	const store = useStore();
	const [name, setName] = useState("");
	const [expression, setExpression] = useState("");
	const [editing, setEditing] = useState<string | null>(null);
	const [error, setError] = useState("");
	const reset = () => { setName(""); setExpression(""); setEditing(null); setError(""); };
	const save = () => {
		const key = name.trim();
		const problem = validateCalculatorVariableName(key);
		if (problem) { setError(problem); return; }
		if (key !== editing && Object.hasOwn(store.ui.calculatorVariables, key)) { setError("This variable already exists. Edit it instead."); return; }
		const next = { ...store.ui.calculatorVariables };
		if (editing && editing !== key) delete next[editing];
		next[key] = expression.trim().replace(/^(["'])(.*)\1$/, "$2");
		if (!next[key] || next[key].length > 4096) { setError("Use an expression between 1 and 4096 characters."); return; }
		try {
			for (const variable of Object.keys(next)) {
				const expanded = expandCalculatorVariables(variable, next);
				if (!isCalculatorExpressionCandidate(expanded)) throw new Error(`Invalid expression or unknown reference in ${variable}.`);
			}
			store.ui.setCalculatorVariables(next); reset();
		} catch (reason) { setError(reason instanceof Error ? reason.message : "Invalid variable."); }
	};
	return <View className="p-2.5 subBg gap-2 rounded-lg border border-lightBorder dark:border-darkBorder">
		<Text className="text-sm text">Variables</Text>
		<Text className="text-xs darker-text">Reusable expressions, with units and references to other variables. Names are case-sensitive; built-in units and constants are reserved.</Text>
		{Object.entries(store.ui.calculatorVariables).map(([key, value]) => <View key={key} className="flex-row gap-2 items-center">
			<TouchableOpacity className="flex-1" onPress={() => { setEditing(key); setName(key); setExpression(value); setError(""); }}><Text className="text-sm text">{key} = {value}</Text></TouchableOpacity>
			<TouchableOpacity accessibilityLabel={`Delete variable ${key}`} onPress={() => {
				const next = { ...store.ui.calculatorVariables }; delete next[key];
				try {
				if (Object.keys(next).some((other) => !isCalculatorExpressionCandidate(expandCalculatorVariables(other, next)))) { setError("Another variable depends on this one. Edit or remove it first."); return; }
				store.ui.setCalculatorVariables(next); if (editing === key) reset();
				} catch (reason) { setError(reason instanceof Error ? reason.message : "Invalid variable."); }
			}}><Text className="text-xs text-red-500">Delete</Text></TouchableOpacity>
		</View>)}
		<Input bordered placeholder="Name (e.g. zzz)" value={name} onChangeText={setName} />
		<Input bordered placeholder="Expression (e.g. 2384 m/s)" value={expression} onChangeText={setExpression} onSubmitEditing={save} />
		{error ? <Text className="text-xs text-red-500">{error}</Text> : null}
		<View className="flex-row gap-4"><TouchableOpacity onPress={save}><Text className="text-sm text">{editing ? "Save" : "Add variable"}</Text></TouchableOpacity>{editing && <TouchableOpacity onPress={reset}><Text className="text-sm darker-text">Cancel</Text></TouchableOpacity>}</View>
	</View>;
});

const CurrencyRateSettings = observer(() => {
	const store = useStore();
	const [interval, setIntervalValue] = useState(
		String(store.ui.currencyRefreshIntervalMinutes),
	);

	useEffect(() => {
		setIntervalValue(String(store.ui.currencyRefreshIntervalMinutes));
	}, [store.ui.currencyRefreshIntervalMinutes]);

	const parsedInterval = Number(interval);
	const intervalIsValid =
		Number.isInteger(parsedInterval) &&
		parsedInterval >= MIN_CURRENCY_REFRESH_INTERVAL_MINUTES &&
		parsedInterval <= MAX_CURRENCY_REFRESH_INTERVAL_MINUTES;
	const snapshot = store.currencyRates.snapshot;
	const numberFormatter = new Intl.NumberFormat(undefined, {
		maximumSignificantDigits: 8,
	});
	const snapshotSummary = snapshot
		? `1 EUR = ${numberFormatter.format(Number(snapshot.rates.USD))} USD · 1 BTC = ${numberFormatter.format(1 / Number(snapshot.rates.BTC))} EUR`
		: "No exchange rate cached yet";
	const timestamp = snapshot
		? new Date(snapshot.fetchedAt).toLocaleString()
		: null;

	return (
		<View className="p-2.5 subBg gap-2 rounded-lg border border-lightBorder dark:border-darkBorder">
			<View>
				<Text className="text-sm text">Currency rates</Text>
				<Text className="text-xxs text-neutral-500 dark:text-neutral-400 mt-1">
					EUR, USD and BTC exchange rates
				</Text>
			</View>

			<View className="border-t border-lightBorder dark:border-darkBorder" />

			<View className="flex-row items-center gap-2">
				<View className="flex-1">
					<Text className="text-sm text">Refresh interval</Text>
					<Text className="text-xxs text-neutral-500 dark:text-neutral-400">
						1–1,440 minutes; 10 minutes by default
					</Text>
				</View>
				<Input
					bordered
					className="w-20 h-7"
					inputClassName="text-right"
					value={interval}
					onChangeText={setIntervalValue}
				/>
				<Text className="text-xs darker-text w-7">min</Text>
			</View>

			<Text className="text-xxs darker-text" numberOfLines={1}>
				{snapshotSummary}
			</Text>
			<Text className="text-xxs text-neutral-500 dark:text-neutral-400">
				{store.currencyRates.isRefreshing
					? "Refreshing…"
					: timestamp
						? `Retrieved ${timestamp}`
						: store.currencyRates.lastError ?? "Waiting for the first refresh"}
			</Text>

			{!intervalIsValid && (
				<Text className="text-xs text-red-500">
					Use a whole number from 1 to 1,440.
				</Text>
			)}

			<View className="flex-row justify-end gap-2">
				<TouchableOpacity
					onPress={() => void store.currencyRates.refresh()}
				>
					<View className="px-3 py-1.5 rounded-md border border-color">
						<Text className="text-xs text">Refresh now</Text>
					</View>
				</TouchableOpacity>
				<TouchableOpacity
					onPress={() => {
						setIntervalValue(
							String(DEFAULT_CURRENCY_REFRESH_INTERVAL_MINUTES),
						);
						store.ui.setCurrencyRefreshIntervalMinutes(
							DEFAULT_CURRENCY_REFRESH_INTERVAL_MINUTES,
						);
					}}
				>
					<View className="px-3 py-1.5 rounded-md border border-color">
						<Text className="text-xs text">Reset</Text>
					</View>
				</TouchableOpacity>
				<TouchableOpacity
					disabled={!intervalIsValid}
					onPress={() => {
						if (!intervalIsValid) return;
						store.ui.setCurrencyRefreshIntervalMinutes(parsedInterval);
					}}
				>
					<View
						className={clsx("px-3 py-1.5 rounded-md", {
							"bg-accent-strong": intervalIsValid,
							"bg-neutral-300 dark:bg-neutral-700": !intervalIsValid,
						})}
					>
						<Text className="text-xs text-white">Apply</Text>
					</View>
				</TouchableOpacity>
			</View>
		</View>
	);
});

export const CalculatorSettings = observer(() => {
 const store = useStore();
 return <ScrollView className="flex-1" contentContainerClassName="p-3 gap-3">
 <CurrencyRateSettings />
 <VariableSettings />
			<View className="p-2.5 subBg gap-2 rounded-lg border border-lightBorder dark:border-darkBorder">
				<Text className="text-sm text">Calculator date format</Text>
				<Input value={store.ui.calculatorDateFormat}
					onChangeText={(value) => store.ui.setCalculatorDateFormat(value)}
					placeholder="YYYY-MM-DD" />
				<Text className="text-xxs darker-text">YYYY: year · MM: month · DD: day · dddd: weekday · ddd: short weekday. Example: dddd YYYY-MM-DD. Local timezone; now adds HH:mm.</Text>
			</View>
 <View className="p-2.5 subBg gap-2 rounded-lg border border-lightBorder dark:border-darkBorder">
 <View className="flex-row items-center gap-3"><Text className="flex-1 text-sm text">Enable month unit (30 days)</Text><MySwitch value={store.ui.calculatorMonthsEnabled} onValueChange={store.ui.setCalculatorMonthsEnabled} /></View>
 <Text className="text-xs darker-text">Disabled by default. month, months and mo use exactly 30 days. Results include a warning and an alternative using 365.25 / 12 = 30.4375 days. Neither convention represents an actual calendar month.</Text>
 </View>
 </ScrollView>;
});
