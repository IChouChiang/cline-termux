import type { TranscriptCommand } from "./transcript-keybinds";

type ArrowKey = {
	name: string;
	ctrl: boolean;
	meta: boolean;
	option?: boolean;
	shift: boolean;
};

export function shouldHandleInputHistory(input: {
	isRunning: boolean;
	hasQueuedPrompts: boolean;
}): boolean {
	return !input.isRunning || !input.hasQueuedPrompts;
}

export function matchTermuxTranscriptTouchScrollKey(input: {
	enabled: boolean;
	key: ArrowKey;
	hasTranscript: boolean;
}): TranscriptCommand | null {
	if (!input.enabled || !input.hasTranscript) return null;
	if (input.key.ctrl || input.key.meta || input.key.option || input.key.shift) {
		return null;
	}

	if (input.key.name === "up") return "messages_line_up";
	if (input.key.name === "down") return "messages_line_down";
	return null;
}
