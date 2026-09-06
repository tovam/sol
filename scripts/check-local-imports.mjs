import { execFileSync } from "node:child_process";
import { readFileSync } from "node:fs";
import { createRequire } from "node:module";
import path from "node:path";
import { fileURLToPath } from "node:url";

const require = createRequire(import.meta.url);
const ts = require("typescript");
const repository = fileURLToPath(new URL("../", import.meta.url));
const sourceRoot = path.join(repository, "src");

// Inspect tracked source declarations only. Never execute the application or
// load local configuration, installed packages, or persisted runtime state.
const filenames = execFileSync("git", ["ls-files", "-z", "--", "src"], {
	cwd: repository,
	encoding: "utf8",
})
	.split("\0")
	.filter((filename) => /\.(?:ts|tsx)$/.test(filename))
	.filter(
		(filename) =>
			!filename.split("/").some((part) =>
				/^(?:\.?env(?:\.|$)|secrets?(?:\.|$)|data$|logs?$|caches?$)/i.test(part),
			),
	)
	.map((filename) => path.join(repository, filename));
const sources = new Map(
	filenames.map((filename) => [
		filename,
		ts.createSourceFile(
			filename,
			readFileSync(filename, "utf8"),
			ts.ScriptTarget.Latest,
			true,
		),
	]),
);

function resolveLocalModule(specifier, importer) {
	const base = specifier.startsWith(".")
		? path.resolve(path.dirname(importer), specifier)
		: path.resolve(sourceRoot, specifier);
	return [
		base,
		`${base}.macos.ts`,
		`${base}.macos.tsx`,
		`${base}.native.ts`,
		`${base}.native.tsx`,
		`${base}.ts`,
		`${base}.tsx`,
		`${base}.d.ts`,
		path.join(base, "index.ts"),
		path.join(base, "index.tsx"),
	].find((filename) => sources.has(filename));
}

const program = ts.createProgram(
	filenames,
	{
		noEmit: true,
		noLib: true,
		noResolve: true,
		target: ts.ScriptTarget.Latest,
		module: ts.ModuleKind.ESNext,
		jsx: ts.JsxEmit.Preserve,
	},
	{
		getSourceFile: (filename) => sources.get(filename),
		getDefaultLibFileName: () => "",
		writeFile: () => {},
		getCurrentDirectory: () => repository,
		getDirectories: () => [],
		fileExists: (filename) => sources.has(filename),
		readFile: (filename) => sources.get(filename)?.text,
		getCanonicalFileName: (filename) => filename,
		useCaseSensitiveFileNames: () => true,
		getNewLine: () => "\n",
		resolveModuleNames: (specifiers, importer) =>
			specifiers.map((specifier) => {
				const resolvedFileName = resolveLocalModule(specifier, importer);
				return resolvedFileName ? { resolvedFileName } : undefined;
			}),
	},
);
const checker = program.getTypeChecker();
let importCount = 0;
let failures = 0;

for (const source of sources.values()) {
	for (const statement of source.statements) {
		if (!ts.isImportDeclaration(statement) || !statement.importClause) continue;
		const target = resolveLocalModule(
			statement.moduleSpecifier.text,
			source.fileName,
		);
		if (!target) continue; // External packages and native assets belong to Metro.
		const symbol = checker.getSymbolAtLocation(sources.get(target));
		const exports = new Set(
			symbol ? checker.getExportsOfModule(symbol).map((item) => item.name) : [],
		);
		const clause = statement.importClause;
		const names = clause.name ? ["default"] : [];
		if (clause.namedBindings && ts.isNamedImports(clause.namedBindings)) {
			names.push(
				...clause.namedBindings.elements.map(
					(item) => (item.propertyName ?? item.name).text,
				),
			);
		}
		for (const name of names) {
			importCount += 1;
			if (exports.has(name)) continue;
			failures += 1;
			const { line } = source.getLineAndCharacterOfPosition(
				statement.getStart(),
			);
			console.error(
				`${path.relative(repository, source.fileName)}:${line + 1}: ` +
				`"${statement.moduleSpecifier.text}" does not export "${name}".`,
			);
		}
	}
}

console.log(`Checked ${importCount} local imports in ${sources.size} source files.`);
if (failures) process.exitCode = 1;
