import { type Env, isTermuxRuntime } from "./termux-runtime";

export type TermuxTouchScrollMode = "input" | "transcript";

const TERMUX_TOUCH_SCROLL_ENV = "CLINE_TUI_TERMUX_TOUCH_SCROLL";
const DEFAULT_TERMUX_TOUCH_SCROLL_MODE: TermuxTouchScrollMode = "transcript";
const TRANSCRIPT_VALUES = new Set([
	"1",
	"true",
	"yes",
	"on",
	"scroll",
	"transcript",
	"messages",
]);
const INPUT_VALUES = new Set([
	"0",
	"false",
	"no",
	"off",
	"input",
	"history",
	"keyboard",
]);

function parseTermuxTouchScrollMode(
	value: string | undefined,
): TermuxTouchScrollMode | undefined {
	const normalized = value?.trim().toLowerCase();
	if (!normalized || normalized === "auto") return undefined;
	if (TRANSCRIPT_VALUES.has(normalized)) return "transcript";
	if (INPUT_VALUES.has(normalized)) return "input";
	return undefined;
}

export function getTermuxTouchScrollMode(
	env: Env = process.env,
): TermuxTouchScrollMode {
	if (!isTermuxRuntime(env)) return "input";
	return (
		parseTermuxTouchScrollMode(env[TERMUX_TOUCH_SCROLL_ENV]) ??
		DEFAULT_TERMUX_TOUCH_SCROLL_MODE
	);
}

export function shouldUseTermuxTranscriptTouchScroll(
	env: Env = process.env,
): boolean {
	return getTermuxTouchScrollMode(env) === "transcript";
}
