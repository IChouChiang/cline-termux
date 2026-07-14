#!/usr/bin/env node

import { existsSync, readFileSync, realpathSync, writeFileSync } from "node:fs";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const scriptDir = dirname(fileURLToPath(import.meta.url));
const repoRoot = resolve(scriptDir, "..");

function fail(message) {
	console.error(`[fail] ${message}`);
	process.exit(1);
}

function readJson(path) {
	return JSON.parse(readFileSync(path, "utf8"));
}

function writeJson(path, value) {
	writeFileSync(path, `${JSON.stringify(value, null, 2)}\n`);
}

function resolvedDependencyVersion(packageName) {
	const packagePath = join(
		repoRoot,
		"apps/cli/node_modules",
		packageName,
		"package.json",
	);
	if (!existsSync(packagePath)) {
		fail(`dependency is not installed: ${packageName}`);
	}
	return readJson(realpathSync(packagePath)).version;
}

function updatePortMetadata() {
	const [upstreamTag, upstreamCommit, releaseTag] = process.argv.slice(3);
	if (!upstreamTag || !upstreamCommit || !releaseTag) {
		fail("update requires UPSTREAM_TAG UPSTREAM_COMMIT RELEASE_TAG");
	}

	const rootPackagePath = join(repoRoot, "package.json");
	const cliPackage = readJson(join(repoRoot, "apps/cli/package.json"));
	const rootPackage = readJson(rootPackagePath);
	const manifestPath = join(scriptDir, "port-manifest.json");
	const manifest = readJson(manifestPath);
	const revisionMatch = releaseTag.match(/-termux\.(\d+)$/);
	if (!revisionMatch) fail(`invalid Termux release tag: ${releaseTag}`);

	rootPackage.patchedDependencies = {
		"@opentui-ui/dialog@0.1.2": "patches/@opentui-ui%2Fdialog@0.1.2.patch",
	};
	writeJson(rootPackagePath, rootPackage);

	manifest.upstream.tag = upstreamTag;
	manifest.upstream.commit = upstreamCommit;
	manifest.upstream.cliVersion = cliPackage.version;
	manifest.termux.releaseTag = releaseTag;
	manifest.termux.revision = Number(revisionMatch[1]);
	manifest.toolchain.bun = rootPackage.engines?.bun ?? "";
	manifest.toolchain.node = rootPackage.engines?.node ?? "";
	manifest.openTui.core = cliPackage.dependencies["@opentui/core"];
	manifest.openTui.react = cliPackage.dependencies["@opentui/react"];
	manifest.openTui.dialog = cliPackage.dependencies[
		"@opentui-ui/dialog"
	].replace(/^\^/, "");
	writeJson(manifestPath, manifest);

	const readmePath = join(repoRoot, "README.md");
	const readme = readFileSync(readmePath, "utf8")
		.replace(/^Cline CLI: .+$/m, `Cline CLI: ${cliPackage.version}`)
		.replace(/^Termux release: .+$/m, `Termux release: ${releaseTag}`);
	writeFileSync(readmePath, readme);
}

function writeRuntimePackage() {
	const [outputPath, releaseVersion] = process.argv.slice(3);
	if (!outputPath || !releaseVersion) {
		fail("runtime-package requires OUTPUT_PATH RELEASE_VERSION");
	}

	const runtimePackages = [
		"@opentui-ui/dialog",
		"@opentui/core",
		"@opentui/react",
		"opentui-spinner",
		"react",
		"react-devtools-core",
		"react-reconciler",
	];
	const dependencies = Object.fromEntries(
		runtimePackages.map((name) => [name, resolvedDependencyVersion(name)]),
	);
	dependencies["@opentui/core-android-arm64"] =
		`npm:@opentui/core-linux-arm64@${dependencies["@opentui/core"]}`;

	writeJson(outputPath, {
		name: "cline-termux",
		version: releaseVersion,
		private: true,
		type: "module",
		description: `Cline CLI packaged for Termux Android aarch64`,
		bin: { cline: "./index.js" },
		os: ["android"],
		cpu: ["arm64"],
		dependencies,
		patchedDependencies: {
			"@opentui-ui/dialog@0.1.2": "patches/@opentui-ui%2Fdialog@0.1.2.patch",
		},
	});
}

switch (process.argv[2]) {
	case "update":
		updatePortMetadata();
		break;
	case "runtime-package":
		writeRuntimePackage();
		break;
	default:
		fail("expected command: update or runtime-package");
}
