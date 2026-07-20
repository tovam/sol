import { forwardRef } from "react";
import {
	StyleSheet,
	TextInput as NativeTextInput,
	type TextInputProps as NativeTextInputProps,
} from "react-native-macos";

export type TextInputHandle = NativeTextInput;
export type TextInputProps = NativeTextInputProps & { className?: string };

export const TextInput = forwardRef<TextInputHandle, TextInputProps>(
	function TextInput(
		{ multiline = false, numberOfLines, style, ...props },
		ref,
	) {
		return (
			<NativeTextInput
				{...props}
				ref={ref}
				multiline={multiline}
				numberOfLines={multiline ? numberOfLines : 1}
				style={[STYLES.input, style]}
			/>
		);
	},
);

const STYLES = StyleSheet.create({
	input: {
		flexShrink: 1,
		minWidth: 0,
		width: "100%",
	},
});
