import { getDefaultShell } from "@cline/shared";
import { afterEach, describe, expect, it } from "vitest";

// The shell tool spawns getDefaultShell(process.platform). Upstream hardcodes
// /bin/bash for every non-Windows platform, which Android does not have; the
// port's Android branch lives in sdk/packages/shared/src/parse/shell.ts.
describe("getDefaultShell on Termux", () => {
	const originalPrefix = process.env.PREFIX;

	afterEach(() => {
		if (originalPrefix === undefined) {
			delete process.env.PREFIX;
		} else {
			process.env.PREFIX = originalPrefix;
		}
	});

	it("uses Termux's bash under $PREFIX on Android", () => {
		process.env.PREFIX = "/data/data/com.termux/files/usr";
		expect(getDefaultShell("android")).toBe(
			"/data/data/com.termux/files/usr/bin/bash",
		);
	});

	it("falls back to the system shell on Android without $PREFIX", () => {
		delete process.env.PREFIX;
		expect(getDefaultShell("android")).toBe("/system/bin/sh");
	});

	it("keeps upstream's defaults on other platforms", () => {
		process.env.PREFIX = "/data/data/com.termux/files/usr";
		expect(getDefaultShell("linux")).toBe("/bin/bash");
		expect(getDefaultShell("darwin")).toBe("/bin/bash");
		expect(getDefaultShell("win32")).toBe("powershell");
	});
});
