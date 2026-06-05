import type { DialogContainerOptions } from "@opentui-ui/dialog/react";
import { isTermuxRuntime, type Env } from "./termux-runtime";

type DialogProviderSafeAreaOptions = Pick<
	DialogContainerOptions,
	"safeAreaBottom" | "verticalAlign"
>;

const DEFAULT_TERMUX_DIALOG_SAFE_AREA_BOTTOM = "15%" as const;

function parseSafeAreaValue(
	value: string | undefined,
): DialogProviderSafeAreaOptions["safeAreaBottom"] | undefined {
	const trimmed = value?.trim();
	if (!trimmed) return undefined;
	if (/^\d+(?:\.\d+)?%$/.test(trimmed)) {
		return trimmed as `${number}%`;
	}
	const rows = Number(trimmed);
	if (!Number.isFinite(rows) || rows < 0) return undefined;
	return Math.floor(rows);
}

export function getTermuxDialogSafeAreaOptions(
	env: Env = process.env,
): DialogProviderSafeAreaOptions {
	if (!isTermuxRuntime(env)) return {};
	return {
		verticalAlign: "center",
		safeAreaBottom:
			parseSafeAreaValue(env.CLINE_TUI_TERMUX_DIALOG_SAFE_AREA_BOTTOM) ??
			DEFAULT_TERMUX_DIALOG_SAFE_AREA_BOTTOM,
	};
}
