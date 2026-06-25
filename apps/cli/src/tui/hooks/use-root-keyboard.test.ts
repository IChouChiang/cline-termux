import { describe, expect, it } from "vitest";
import {
	matchTermuxTranscriptTouchScrollKey,
	shouldHandleInputHistory,
} from "./root-keyboard-routing";

function key(input: {
	name: string;
	ctrl?: boolean;
	meta?: boolean;
	option?: boolean;
	shift?: boolean;
}) {
	return {
		name: input.name,
		ctrl: input.ctrl ?? false,
		meta: input.meta ?? false,
		option: input.option ?? false,
		shift: input.shift ?? false,
	};
}

describe("root keyboard input history routing", () => {
	it("handles history while idle", () => {
		expect(
			shouldHandleInputHistory({
				isRunning: false,
				hasQueuedPrompts: false,
			}),
		).toBe(true);
	});

	it("handles history during a running turn when the prompt queue is empty", () => {
		expect(
			shouldHandleInputHistory({
				isRunning: true,
				hasQueuedPrompts: false,
			}),
		).toBe(true);
	});

	it("keeps running-turn arrow keys reserved for queued prompts when the queue is populated", () => {
		expect(
			shouldHandleInputHistory({
				isRunning: true,
				hasQueuedPrompts: true,
			}),
		).toBe(false);
	});
});

describe("matchTermuxTranscriptTouchScrollKey", () => {
	it("maps unmodified arrows to transcript line scroll when enabled", () => {
		expect(
			matchTermuxTranscriptTouchScrollKey({
				enabled: true,
				hasTranscript: true,
				key: key({ name: "up" }),
			}),
		).toBe("messages_line_up");
		expect(
			matchTermuxTranscriptTouchScrollKey({
				enabled: true,
				hasTranscript: true,
				key: key({ name: "down" }),
			}),
		).toBe("messages_line_down");
	});

	it("leaves normal input history routing untouched unless fully enabled", () => {
		expect(
			matchTermuxTranscriptTouchScrollKey({
				enabled: false,
				hasTranscript: true,
				key: key({ name: "up" }),
			}),
		).toBe(null);
		expect(
			matchTermuxTranscriptTouchScrollKey({
				enabled: true,
				hasTranscript: false,
				key: key({ name: "down" }),
			}),
		).toBe(null);
	});

	it("does not capture modified navigation keys", () => {
		expect(
			matchTermuxTranscriptTouchScrollKey({
				enabled: true,
				hasTranscript: true,
				key: key({ name: "up", ctrl: true }),
			}),
		).toBe(null);
		expect(
			matchTermuxTranscriptTouchScrollKey({
				enabled: true,
				hasTranscript: true,
				key: key({ name: "down", shift: true }),
			}),
		).toBe(null);
		expect(
			matchTermuxTranscriptTouchScrollKey({
				enabled: true,
				hasTranscript: true,
				key: key({ name: "up", meta: true }),
			}),
		).toBe(null);
		expect(
			matchTermuxTranscriptTouchScrollKey({
				enabled: true,
				hasTranscript: true,
				key: key({ name: "down", option: true }),
			}),
		).toBe(null);
	});
});
