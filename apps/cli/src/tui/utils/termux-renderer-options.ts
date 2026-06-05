import type { CliRendererConfig } from "@opentui/core";
import { isTermuxRuntime, type Env } from "./termux-runtime";

type TermuxRendererOptions = Pick<CliRendererConfig, "useMouse">;

const TERMUX_MOUSE_ENV = "CLINE_TUI_TERMUX_MOUSE";
const DEFAULT_TERMUX_USE_MOUSE = false;
const ENABLE_MOUSE_VALUES = new Set(["1", "true", "yes", "on", "mouse"]);
const DISABLE_MOUSE_VALUES = new Set(["0", "false", "no", "off", "keyboard"]);

function parseTermuxMouseSetting(value: string | undefined): boolean | undefined {
	const normalized = value?.trim().toLowerCase();
	if (!normalized || normalized === "auto") return undefined;
	if (ENABLE_MOUSE_VALUES.has(normalized)) return true;
	if (DISABLE_MOUSE_VALUES.has(normalized)) return false;
	return undefined;
}

export function getTermuxRendererOptions(
	env: Env = process.env,
): TermuxRendererOptions {
	if (!isTermuxRuntime(env)) return {};

	const useMouse = parseTermuxMouseSetting(env[TERMUX_MOUSE_ENV]);
	return { useMouse: useMouse ?? DEFAULT_TERMUX_USE_MOUSE };
}
