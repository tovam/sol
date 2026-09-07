import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";
import { analyzeFileSearchEdit } from "../src/lib/fileSearch.ts";

test("repeated characters can make a post-edit selection look like a pre-edit selection", () => {
	assert.deepEqual(analyzeFileSearchEdit("100/7", "1100/7", { start: 0, end: 0 }).nextSelection, { start: 1, end: 1 });
	assert.deepEqual(analyzeFileSearchEdit("100/7", "1100/7", { start: 1, end: 1 }).nextSelection, { start: 2, end: 2 });
});

test("search input observes native selection without imposing the speculative caret", () => {
	const source = readFileSync(new URL("../src/components/MainInput.tsx", import.meta.url), "utf8");
	assert.doesNotMatch(source, /\bselection\s*=\s*\{/);
	assert.doesNotMatch(source, /selectionRef\.current\s*=\s*store\.ui\.setQueryFromInput/);
	assert.match(source, /selectionRef\.current\s*=\s*event\.nativeEvent\.selection/);
});
