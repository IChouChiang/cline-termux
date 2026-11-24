import {
	CLINE_CONNECTOR_CLI_LAUNCH_ENV,
	readConnectorCliLaunchSpec,
	setConnectorCliLaunchSpec,
} from "@cline/shared";
import { afterEach, describe, expect, it } from "vitest";
import { __test__ } from "./connectors";

// The Termux port runs the CLI as a JS bundle on a plain Bun. Upstream's
// connector command knows a source checkout and a compiled binary only, and
// for the port's shape it would build `bun connect ...`: not the CLI at all,
// and a start of the runtime in the workspace without the launcher's flags
// (apps/cli/src/utils/termux-runtime-flags.ts). The port reuses the command
// the hosting CLI recorded for itself instead. The runtime reports its script
// by the real path, so the config file and the script name the same release
// tree even though the launcher starts `current/index.js`.
const TERMUX_BUN =
	"/data/data/com.termux/files/usr/opt/bun-android-ffi/current/bun";
const HOST_PREFIX = [
	"--config=/data/data/com.termux/files/usr/opt/cline-termux/1.2.3-termux.1/cline-termux-runtime.toml",
	"--no-env-file",
	"/data/data/com.termux/files/usr/opt/cline-termux/1.2.3-termux.1/index.js",
	"connect",
];

describe("connector launch command on the Termux port", () => {
	const originalLaunchSpec = process.env[CLINE_CONNECTOR_CLI_LAUNCH_ENV];

	afterEach(() => {
		if (originalLaunchSpec === undefined) {
			delete process.env[CLINE_CONNECTOR_CLI_LAUNCH_ENV];
		} else {
			process.env[CLINE_CONNECTOR_CLI_LAUNCH_ENV] = originalLaunchSpec;
		}
	});

	it("reuses the hosting CLI's command for a bundle on a plain Bun", () => {
		setConnectorCliLaunchSpec({
			launcher: TERMUX_BUN,
			connectArgsPrefix: HOST_PREFIX,
			cwd: "/workspace",
		});

		expect(
			__test__.buildCliConnectCommand(["telegram", "-k", "token"], {
				execPath: TERMUX_BUN,
				cliPath: "/data/data/com.termux/files/usr/opt/cli/src/index.ts",
				exists: () => false,
			}),
		).toEqual({
			launcher: TERMUX_BUN,
			childArgs: [...HOST_PREFIX, "telegram", "-k", "token"],
		});
	});

	it("gives the same command again after it was registered for the Hub", () => {
		setConnectorCliLaunchSpec({
			launcher: TERMUX_BUN,
			connectArgsPrefix: HOST_PREFIX,
			cwd: "/workspace",
		});
		const options = {
			execPath: TERMUX_BUN,
			cliPath: "/data/data/com.termux/files/usr/opt/cli/src/index.ts",
			exists: () => false,
		};

		const first = __test__.buildCliConnectCommand([], options);
		setConnectorCliLaunchSpec({
			launcher: first.launcher,
			connectArgsPrefix: first.childArgs,
			cwd: "/another/workspace",
		});

		expect(__test__.buildCliConnectCommand([], options)).toEqual(first);
		expect(readConnectorCliLaunchSpec()?.connectArgsPrefix).toEqual(
			HOST_PREFIX,
		);
	});

	it("keeps upstream's command when no hosting CLI recorded one", () => {
		delete process.env[CLINE_CONNECTOR_CLI_LAUNCH_ENV];

		expect(
			__test__.buildCliConnectCommand(["telegram"], {
				execPath: TERMUX_BUN,
				cliPath: "/data/data/com.termux/files/usr/opt/cli/src/index.ts",
				exists: () => false,
			}),
		).toEqual({ launcher: TERMUX_BUN, childArgs: ["connect", "telegram"] });
	});

	it("leaves a source checkout and a compiled binary to upstream's rules", () => {
		setConnectorCliLaunchSpec({
			launcher: TERMUX_BUN,
			connectArgsPrefix: HOST_PREFIX,
			cwd: "/workspace",
		});

		expect(
			__test__.buildCliConnectCommand(["telegram"], {
				execPath: "/Users/test/.bun/bin/bun",
				cliPath: "/repo/apps/cli/src/index.ts",
				exists: () => true,
			}),
		).toEqual({
			launcher: "/Users/test/.bun/bin/bun",
			childArgs: [
				"--conditions=development",
				"/repo/apps/cli/src/index.ts",
				"connect",
				"telegram",
			],
		});
		expect(
			__test__.buildCliConnectCommand(["telegram"], {
				execPath: "/Applications/Cline/bin/cline",
				cliPath: "/repo/apps/cli/src/index.ts",
				exists: () => false,
			}),
		).toEqual({
			launcher: "/Applications/Cline/bin/cline",
			childArgs: ["connect", "telegram"],
		});
	});
});
