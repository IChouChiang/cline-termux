import { mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import {
	buildCliSubcommandCommand,
	resolveCliLaunchSpec,
} from "./internal-launch";
import { inheritedRuntimeFlags } from "./termux-runtime-flags";
import { applyInheritedRuntimeFlags } from "./termux-runtime-launchers";

// The Termux launcher (release/run-cline-termux.sh) starts the bundle with
// `--config=<file in the release tree> --no-env-file`, so that a bunfig.toml
// or .env in the launch folder is not read. These tests cover the other half:
// every copy of the runtime that Cline starts itself gets the same flags.
const CONFIG_FLAG =
	"--config=/opt/cline-termux/1.2.3-termux.1/cline-termux-runtime.toml";
const FLAGS = [CONFIG_FLAG, "--no-env-file"];

describe("inheritedRuntimeFlags", () => {
	it("keeps the two launch-folder flags and nothing else", () => {
		expect(
			inheritedRuntimeFlags([
				"--conditions=development",
				CONFIG_FLAG,
				"--inspect=127.0.0.1:0",
				"--no-env-file",
				"--smol",
			]),
		).toEqual(FLAGS);
	});

	it("returns nothing when the runtime was started without them", () => {
		expect(inheritedRuntimeFlags([])).toEqual([]);
		expect(inheritedRuntimeFlags(["--conditions=development"])).toEqual([]);
	});
});

describe("applyInheritedRuntimeFlags", () => {
	let scratch: string;
	let entryPath: string;

	beforeEach(() => {
		scratch = mkdtempSync(join(tmpdir(), "cline-termux-flags-"));
		entryPath = join(scratch, "entry.js");
		writeFileSync(entryPath, 'import "./index.js";\n');
	});

	afterEach(() => {
		rmSync(scratch, { recursive: true, force: true });
	});

	it("starts the Hub daemon and the plugin sandbox with the flags", () => {
		const setHubLauncher = vi.fn();
		const setPluginLauncher = vi.fn();

		const applied = applyInheritedRuntimeFlags({
			execArgv: FLAGS,
			execPath: "/opt/bun-android-ffi/current/bun",
			env: {},
			hubDaemonEntryPath: entryPath,
			setHubLauncher,
			setPluginLauncher,
		});

		expect(applied).toEqual(FLAGS);
		expect(setHubLauncher).toHaveBeenCalledExactlyOnceWith({
			command: "/opt/bun-android-ffi/current/bun",
			args: [...FLAGS, entryPath],
		});
		expect(setPluginLauncher).toHaveBeenCalledExactlyOnceWith({
			command: "/opt/bun-android-ffi/current/bun",
			argsPrefix: FLAGS,
		});
	});

	it("changes nothing when the runtime was started without the flags", () => {
		const setHubLauncher = vi.fn();
		const setPluginLauncher = vi.fn();

		const applied = applyInheritedRuntimeFlags({
			execArgv: ["--conditions=development"],
			execPath: "/usr/local/bin/bun",
			env: {},
			hubDaemonEntryPath: entryPath,
			setHubLauncher,
			setPluginLauncher,
		});

		expect(applied).toEqual([]);
		expect(setHubLauncher).not.toHaveBeenCalled();
		expect(setPluginLauncher).not.toHaveBeenCalled();
	});

	it("leaves core's Hub lookup alone when no entry.js sits beside the bundle", () => {
		const setHubLauncher = vi.fn();
		const setPluginLauncher = vi.fn();

		applyInheritedRuntimeFlags({
			execArgv: FLAGS,
			execPath: "/opt/bun-android-ffi/current/bun",
			env: {},
			hubDaemonEntryPath: join(scratch, "missing", "entry.js"),
			setHubLauncher,
			setPluginLauncher,
		});

		expect(setHubLauncher).not.toHaveBeenCalled();
		expect(setPluginLauncher).toHaveBeenCalledOnce();
	});

	it("leaves the plugin sandbox alone when another runtime is named for it", () => {
		const setHubLauncher = vi.fn();
		const setPluginLauncher = vi.fn();

		applyInheritedRuntimeFlags({
			execArgv: FLAGS,
			execPath: "/opt/bun-android-ffi/current/bun",
			env: { CLINE_JS_RUNTIME_PATH: "/usr/bin/node" },
			hubDaemonEntryPath: entryPath,
			setHubLauncher,
			setPluginLauncher,
		});

		expect(setHubLauncher).toHaveBeenCalledOnce();
		expect(setPluginLauncher).not.toHaveBeenCalled();
	});
});

describe("resolveCliLaunchSpec with the launch-folder flags", () => {
	let scratch: string;
	let entryPath: string;

	beforeEach(() => {
		scratch = mkdtempSync(join(tmpdir(), "cline-termux-flags-"));
		entryPath = join(scratch, "index.js");
		writeFileSync(entryPath, "");
	});

	afterEach(() => {
		rmSync(scratch, { recursive: true, force: true });
	});

	it("passes the flags to a relaunch of the bundle, ahead of the script", () => {
		const spec = resolveCliLaunchSpec({
			execPath: "/opt/bun-android-ffi/current/bun",
			argv: ["bun", entryPath],
			execArgv: FLAGS,
			cwd: scratch,
			env: {},
		});

		expect(spec).toEqual({
			launcher: "/opt/bun-android-ffi/current/bun",
			childArgsPrefix: [...FLAGS, entryPath],
			identityPath: entryPath,
			mode: "source",
		});
	});

	it("puts the flags in front of a connector's subcommand", () => {
		const command = buildCliSubcommandCommand("connect", ["telegram"], {
			execPath: "/opt/bun-android-ffi/current/bun",
			argv: ["bun", entryPath],
			execArgv: FLAGS,
			cwd: scratch,
			env: {},
		});

		expect(command).toEqual({
			launcher: "/opt/bun-android-ffi/current/bun",
			childArgs: [...FLAGS, entryPath, "connect", "telegram"],
		});
	});

	it("adds nothing when the runtime was started without the flags", () => {
		const spec = resolveCliLaunchSpec({
			execPath: "/opt/bun-android-ffi/current/bun",
			argv: ["bun", entryPath],
			execArgv: [],
			cwd: scratch,
			env: {},
		});

		expect(spec?.childArgsPrefix).toEqual([entryPath]);
	});
});
