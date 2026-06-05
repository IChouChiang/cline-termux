import { describe, expect, it } from "vitest";
import { getTermuxRendererOptions } from "./termux-renderer-options";

describe("getTermuxRendererOptions", () => {
	it("leaves non-Termux terminals unchanged", () => {
		expect(
			getTermuxRendererOptions({
				HOME: "/home/user",
				CLINE_TUI_TERMUX_MOUSE: "off",
			}),
		).toEqual({});
	});

	it("uses keyboard-first mouse handling by default inside Termux", () => {
		expect(getTermuxRendererOptions({ TERMUX_VERSION: "googleplay.test" })).toEqual(
			{ useMouse: false },
		);
	});

	it("can disable mouse tracking for keyboard-first Termux use", () => {
		expect(
			getTermuxRendererOptions({
				TERMUX_VERSION: "1",
				CLINE_TUI_TERMUX_MOUSE: "off",
			}),
		).toEqual({ useMouse: false });
		expect(
			getTermuxRendererOptions({
				TERMUX_VERSION: "1",
				CLINE_TUI_TERMUX_MOUSE: "keyboard",
			}),
		).toEqual({ useMouse: false });
	});

	it("can force mouse tracking when needed", () => {
		expect(
			getTermuxRendererOptions({
				TERMUX_VERSION: "1",
				CLINE_TUI_TERMUX_MOUSE: "on",
			}),
		).toEqual({ useMouse: true });
		expect(
			getTermuxRendererOptions({
				TERMUX_VERSION: "1",
				CLINE_TUI_TERMUX_MOUSE: "mouse",
			}),
		).toEqual({ useMouse: true });
	});
});
