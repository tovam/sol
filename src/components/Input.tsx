import clsx from "clsx";
import { useBoolean } from "hooks";
import type { FC, MutableRefObject } from "react";
import { View, type StyleProp, type ViewStyle } from "react-native";
import colors from "tailwindcss/colors";
import {
	TextInput,
	type TextInputHandle,
	type TextInputProps,
} from "./TextInput";

interface Props extends Omit<TextInputProps, "style"> {
	inputRef?: MutableRefObject<TextInputHandle | null>;
	style?: StyleProp<ViewStyle>;
	inputStyle?: TextInputProps["style"];
	inputClassName?: string;
	bordered?: boolean;
	className?: string;
	autoFocus?: boolean;
}

export const Input: FC<Props> = ({
	inputRef,
	style,
	inputStyle,
	bordered = false,
	autoFocus,
	inputClassName,
	className,
	onFocus,
	onBlur,
	...props
}) => {
	const [focused, focusOn, focusOff] = useBoolean(autoFocus);
	const [hovered, hoverOn, hoverOff] = useBoolean(false);
	const defaultStyles = "justify-center px-2 py-1 h-8";

	return (
		<View
			//@ts-ignore
			onMouseEnter={hoverOn}
			onMouseLeave={hoverOff}
			style={style}
			className={clsx(defaultStyles, className, {
				"border border-color rounded": bordered && !focused && !hovered,
				"border border-accent rounded": bordered && !!focused,
				"border border-neutral-500 dark:border-white rounded":
					bordered && !focused && !!hovered,
			})}
		>
			<TextInput
				{...props}
				// @ts-ignore
				enableFocusRing={false}
				ref={inputRef}
				onFocus={(event) => {
					focusOn();
					onFocus?.(event);
				}}
				onBlur={(event) => {
					focusOff();
					onBlur?.(event);
				}}
				className={`text-sm flex-1 ${inputClassName}`}
				style={inputStyle}
				autoFocus={autoFocus}
				placeholderTextColor={colors.neutral[400]}
				multiline={props.multiline ?? false}
			/>
		</View>
	);
};
