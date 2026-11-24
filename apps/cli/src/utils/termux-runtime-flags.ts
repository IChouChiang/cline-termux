/**
 * Runtime flags that every copy of this runtime started by Cline must get too.
 *
 * The Termux port runs the JS bundle on a plain Bun (`bun index.js`), not on
 * upstream's compiled binary. A plain Bun reads `bunfig.toml`, and on most
 * builds `.env`, from the folder it starts in, and a `preload` entry there
 * runs before any Cline code. Upstream turned that off for its binaries at
 * compile time (cline/cline#15781). The port turns it off with two launch
 * flags in `release/run-cline-termux.sh`.
 *
 * A flag only covers the process it was passed to, and Cline starts further
 * copies of the runtime with the workspace as their folder: the Hub daemon,
 * the plugin sandbox and detached connectors. Each of them gets the flags of
 * the process that starts it. Where no such flag was passed (a dev run, the
 * test suite, upstream's own builds) nothing is added.
 */
export function inheritedRuntimeFlags(
	execArgv: readonly string[] = process.execArgv,
): string[] {
	return execArgv.filter(
		(arg) => arg === "--no-env-file" || arg.startsWith("--config="),
	);
}
