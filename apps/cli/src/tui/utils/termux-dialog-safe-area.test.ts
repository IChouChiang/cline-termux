import { describe, expect, it } from "vitest";
import { getTermuxDialogSafeAreaOptions } from "./termux-dialog-safe-area";

describe("getTermuxDialogSafeAreaOptions", () => {
	it("leaves non-Termux terminals unchanged", () => {
		expect(getTermuxDialogSafeAreaOptions({ HOME: "/home/user" })).toEqual({});
	});

	it("uses a phone-friendly default inside Termux", () => {
		expect(
			getTermuxDialogSafeAreaOptions({ TERMUX_VERSION: "googleplay.test" }),
		).toEqual({
			verticalAlign: "center",
			safeAreaBottom: "15%",
		});
	});

	it("accepts row and percentage overrides", () => {
		expect(
			getTermuxDialogSafeAreaOptions({
				TERMUX_VERSION: "1",
				CLINE_TUI_TERMUX_DIALOG_SAFE_AREA_BOTTOM: "12",
			}),
		).toMatchObject({ safeAreaBottom: 12 });

		expect(
			getTermuxDialogSafeAreaOptions({
				TERMUX_VERSION: "1",
				CLINE_TUI_TERMUX_DIALOG_SAFE_AREA_BOTTOM: "35%",
			}),
		).toMatchObject({ safeAreaBottom: "35%" });
	});
});
