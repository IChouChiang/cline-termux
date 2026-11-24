import { existsSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { setHubDaemonLauncher, setPluginSandboxLauncher } from "@cline/core";
import { inheritedRuntimeFlags } from "./termux-runtime-flags";

export interface InheritedRuntimeFlagOptions {
	execArgv?: readonly string[];
	execPath?: string;
	env?: NodeJS.ProcessEnv;
	hubDaemonEntryPath?: string;
	setHubLauncher?: typeof setHubDaemonLauncher;
	setPluginLauncher?: typeof setPluginSandboxLauncher;
}

/**
 * The Hub daemon entry beside the bundle, found the way core finds it
 * (`resolveDaemonEntryPath` in sdk/packages/core/src/hub/daemon/index.ts).
 */
function bundledHubDaemonEntryPath(): string {
	return fileURLToPath(new URL("./entry.js", import.meta.url));
}

/**
 * Start the Hub daemon and the plugin sandbox with the runtime flags this
 * process was started with (see `inheritedRuntimeFlags`). Both are spawned by
 * core as `<runtime> <script>`, so without this they would read `bunfig.toml`
 * from the workspace again. Returns the flags it applied.
 */
export function applyInheritedRuntimeFlags(
	options: InheritedRuntimeFlagOptions = {},
): string[] {
	const flags = inheritedRuntimeFlags(options.execArgv);
	const execPath = (options.execPath ?? process.execPath)?.trim();
	if (flags.length === 0 || !execPath) {
		return [];
	}
	const hubDaemonEntryPath =
		options.hubDaemonEntryPath ?? bundledHubDaemonEntryPath();
	// Only a packaged bundle has entry.js beside it. Anywhere else core's own
	// lookup stays in charge, so a Hub start is never pointed at a missing file.
	if (existsSync(hubDaemonEntryPath)) {
		(options.setHubLauncher ?? setHubDaemonLauncher)({
			command: execPath,
			args: [...flags, hubDaemonEntryPath],
		});
	}
	// CLINE_JS_RUNTIME_PATH names another runtime for the plugin sandbox. The
	// flags belong to this runtime, so that choice is left alone.
	const env = options.env ?? process.env;
	if (!env.CLINE_JS_RUNTIME_PATH?.trim()) {
		(options.setPluginLauncher ?? setPluginSandboxLauncher)({
			command: execPath,
			argsPrefix: flags,
		});
	}
	return flags;
}
