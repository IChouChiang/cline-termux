export type Env = Record<string, string | undefined>;

const TERMUX_PREFIX_FRAGMENT = "/com.termux/";

export function isTermuxRuntime(env: Env = process.env): boolean {
	return Boolean(
		env.TERMUX_VERSION ||
			env.TERMUX_APP_PACKAGE ||
			env.PREFIX?.includes(TERMUX_PREFIX_FRAGMENT) ||
			env.HOME?.includes(TERMUX_PREFIX_FRAGMENT),
	);
}
