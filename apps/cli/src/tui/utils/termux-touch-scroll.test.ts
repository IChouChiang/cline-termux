import { describe, expect, it } from "vitest";
import {
	getTermuxTouchScrollMode,
	shouldUseTermuxTranscriptTouchScroll,
} from "./termux-touch-scroll";

describe("getTermuxTouchScrollMode", () => {
	it("keeps non-Termux terminals in input mode", () => {
		expect(
			getTermuxTouchScrollMode({
				HOME: "/home/user",
				CLINE_TUI_TERMUX_TOUCH_SCROLL: "transcript",
			}),
		).toBe("input");
	});

	it("scrolls the transcript by default inside Termux", () => {
		expect(getTermuxTouchScrollMode({ TERMUX_VERSION: "1" })).toBe(
			"transcript",
		);
	});

	it("accepts explicit transcript-mode aliases", () => {
		expect(
			getTermuxTouchScrollMode({
				TERMUX_VERSION: "1",
				CLINE_TUI_TERMUX_TOUCH_SCROLL: "transcript",
			}),
		).toBe("transcript");
		expect(
			shouldUseTermuxTranscriptTouchScroll({
				TERMUX_VERSION: "1",
				CLINE_TUI_TERMUX_TOUCH_SCROLL: "on",
			}),
		).toBe(true);
	});

	it("accepts explicit input-mode aliases", () => {
		expect(
			getTermuxTouchScrollMode({
				TERMUX_VERSION: "1",
				CLINE_TUI_TERMUX_TOUCH_SCROLL: "history",
			}),
		).toBe("input");
		expect(
			getTermuxTouchScrollMode({
				TERMUX_VERSION: "1",
				CLINE_TUI_TERMUX_TOUCH_SCROLL: "off",
			}),
		).toBe("input");
	});
});
