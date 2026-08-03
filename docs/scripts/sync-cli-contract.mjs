import { readFileSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

// docs/cli-contract.md is the single source of truth for the CLI contract;
// this renders it as a site page instead of forking it.
const site = dirname(dirname(fileURLToPath(import.meta.url)));
const source = join(site, "..", "docs", "cli-contract.md");
const target = join(site, "content", "04-cli", "reference.md");

const body = readFileSync(source, "utf8").replace(/^# .*\n+/, "");
const frontmatter = `---
title: CLI reference
description: The stable cap CLI contract — exit codes, JSON fields, TSV columns, and CAP_DIR.
---

`;

writeFileSync(target, frontmatter + body);
console.log(`synced ${source} -> ${target}`);
