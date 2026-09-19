import assert from "node:assert/strict";
import { registerHooks } from "node:module";
import test from "node:test";

// Synthetic transport: never contact the user's running OpenCode instance.
registerHooks({ resolve(specifier, context, nextResolve) {
	if (specifier === "axios") return { shortCircuit: true, url: "data:text/javascript," + encodeURIComponent("export default { post: async (...args) => { globalThis.openCodeRequest = args; } }") };
	return nextResolve(specifier, context);
} });
const { resolveOpenCodePrompt, openCodeMiniSession, DEFAULT_OPENCODE_URL } = await import("../src/lib/openCode.ts");

test("oc preserves the prompt and sends JSON without automatic submission", async () => {
	assert.equal(resolveOpenCodePrompt("oc"), "");
	assert.equal(resolveOpenCodePrompt("OC bonjour é & ?"), "bonjour é & ?");
	assert.equal(resolveOpenCodePrompt("octopus"), null);
	await openCodeMiniSession(DEFAULT_OPENCODE_URL, "bonjour é & ?");
	assert.equal(globalThis.openCodeRequest[0], DEFAULT_OPENCODE_URL);
	assert.deepEqual(globalThis.openCodeRequest[1], { prompt: "bonjour é & ?" });
	await openCodeMiniSession("http://custom.localhost:55555/test", "");
	assert.deepEqual(globalThis.openCodeRequest[1], {});
	await assert.rejects(openCodeMiniSession("file:///bad", "hello"));
	await assert.rejects(openCodeMiniSession(DEFAULT_OPENCODE_URL, "é".repeat(16385)));
});
