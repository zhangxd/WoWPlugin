# Toolbox Data Contract Export Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the current hard-coded `WoWTools` export rules for generated `Toolbox/Data/*.lua` files with `WoWPlugin`-owned JSON contracts, contract-tagged Lua headers, and snapshot-backed export validation for the three current generated data files.

**Architecture:** `WoWPlugin/DataContracts/<contract_id>.json` becomes the source of truth for database-generated Toolbox data. `WoWTools` loads contracts by `contract_id`, validates JSON plus SQL/result aliases plus output structure, renders Lua through fixed root-type writers (`map_scalar`, `map_array`, `document`), writes tagged file headers, and stores immutable contract snapshots under `WoWTools/outputs/toolbox/contract_snapshots/`. `WoWPlugin` adds static validators and data/header alignment checks so drift is caught before runtime.

**Tech Stack:** Python 3, JSON, SQLite, Lua, `unittest`, existing `WoWPlugin` Python + `busted` test harness

---

## Workspace Notes

- `WoWPlugin` is the active git repository in this workspace.
- `../WoWTools` is a sibling directory and is **not** a git repository in the current workspace.
- Use normal commits for `WoWPlugin`-tracked changes.
- For `../WoWTools` changes, do not invent commit steps that cannot run. Use explicit verification checkpoints instead.

## File Structure

### Contract IDs locked for the initial migration

- `instance_map_ids` -> `Toolbox/Data/InstanceMapIDs.lua` -> `Toolbox.Data.InstanceMapIDs` -> `map_scalar`
- `instance_drops_mount` -> `Toolbox/Data/InstanceDrops_Mount.lua` -> `Toolbox.Data.MountDrops` -> `map_array`
- `instance_questlines` -> `Toolbox/Data/InstanceQuestlines.lua` -> `Toolbox.Data.InstanceQuestlines` -> `document`

### Create

- `DataContracts/instance_map_ids.json`
  Responsibility: Contract source of truth for `InstanceMapIDs.lua`
- `DataContracts/instance_drops_mount.json`
  Responsibility: Contract source of truth for `InstanceDrops_Mount.lua`
- `DataContracts/instance_questlines.json`
  Responsibility: Contract source of truth for `InstanceQuestlines.lua`
- `tests/validate_data_contracts.py`
  Responsibility: Plugin-side static validator for contract filenames, required sections, version metadata, and Lua header alignment
- `../WoWTools/scripts/export/contract_model.py`
  Responsibility: Parse and validate contract JSON into typed runtime objects
- `../WoWTools/scripts/export/contract_io.py`
  Responsibility: Resolve contract directory, load/enumerate contracts, and write immutable snapshots
- `../WoWTools/scripts/export/lua_contract_writer.py`
  Responsibility: Build tagged Lua headers and render supported root types
- `../WoWTools/scripts/export/tests/test_contract_model.py`
  Responsibility: Unit tests for JSON parsing and schema validation
- `../WoWTools/scripts/export/tests/test_contract_io.py`
  Responsibility: Unit tests for contract discovery and snapshot writing
- `../WoWTools/scripts/export/tests/test_lua_contract_writer.py`
  Responsibility: Unit tests for header generation and fixed root-type rendering

### Modify

- `tests/run_all.py`
  Responsibility: Run contract validation before the existing static validator
- `tests/validate_settings_subcategories.py`
  Responsibility: Assert generated data files use tagged contract headers and expected contract IDs
- `Toolbox/Data/InstanceMapIDs.lua`
  Responsibility: Regenerated output with `@contract_id instance_map_ids` header
- `Toolbox/Data/InstanceDrops_Mount.lua`
  Responsibility: Regenerated output with `@contract_id instance_drops_mount` header
- `Toolbox/Data/InstanceQuestlines.lua`
  Responsibility: Regenerated output with `@contract_id instance_questlines` header
- `AGENTS.md`
  Responsibility: Replace header-driven export guidance with contract-driven rules and remove stale special-case text once migrated
- `README.md`
  Responsibility: Document `DataContracts/` as the plugin-side source of truth
- `../WoWTools/README.md`
  Responsibility: Document contract-driven export flow, `--contract-dir`, and snapshot location
- `../WoWTools/scripts/export/toolbox_db_export.py`
  Responsibility: Replace hard-coded `RULES` registry with contract-driven orchestration
- `../WoWTools/scripts/export/export_toolbox_all.py`
  Responsibility: Export all active contracts from `WoWPlugin/DataContracts`
- `../WoWTools/scripts/export/export_toolbox_one.py`
  Responsibility: Export a single contract by `contract_id` (keep output-file fallback only if tests require compatibility)

## Chunk 1: Plugin Contract Source Of Truth

### Task 1: Add contract files and a failing validator first

**Files:**
- Create: `DataContracts/instance_map_ids.json`
- Create: `DataContracts/instance_drops_mount.json`
- Create: `DataContracts/instance_questlines.json`
- Create: `tests/validate_data_contracts.py`

- [ ] **Step 1: Write the failing plugin-side validator**

Add a new validator script that starts with an explicit registry:

```python
EXPECTED_GENERATED_CONTRACTS = {
    "instance_map_ids": {
        "lua_file": "Toolbox/Data/InstanceMapIDs.lua",
        "lua_table": "Toolbox.Data.InstanceMapIDs",
        "root_type": "map_scalar",
    },
    "instance_drops_mount": {
        "lua_file": "Toolbox/Data/InstanceDrops_Mount.lua",
        "lua_table": "Toolbox.Data.MountDrops",
        "root_type": "map_array",
    },
    "instance_questlines": {
        "lua_file": "Toolbox/Data/InstanceQuestlines.lua",
        "lua_table": "Toolbox.Data.InstanceQuestlines",
        "root_type": "document",
    },
}
```

Validate:

- file name equals `contract_id + ".json"`
- top-level sections `contract/output/source/structure/validation/versioning` exist
- `contract.source_of_truth == "WoWPlugin"`
- `versioning.current_schema_version == contract.schema_version`
- `output.lua_file` matches the explicit registry

- [ ] **Step 2: Run the validator to verify it fails**

Run: `python tests/validate_data_contracts.py`

Expected: FAIL with a missing contract file such as `DataContracts/instance_map_ids.json`

- [ ] **Step 3: Add the three initial contract files**

Use minimal but real contract content, not placeholders. For `instance_map_ids.json`, the contract should look structurally like:

```json
{
  "contract": {
    "contract_id": "instance_map_ids",
    "schema_version": 1,
    "summary": "副本 journalInstanceID 到 MapID 的静态映射",
    "source_of_truth": "WoWPlugin",
    "status": "active"
  },
  "output": {
    "lua_file": "Toolbox/Data/InstanceMapIDs.lua",
    "lua_table": "Toolbox.Data.InstanceMapIDs",
    "write_header": true
  },
  "source": {
    "database": "wow.db",
    "tables": ["journalinstance"],
    "sql": "SELECT ...",
    "query": {
      "from": "journalinstance",
      "select": ["journal_instance_id", "map_id", "comment_name"],
      "row_granularity": "one row per journal instance"
    }
  },
  "structure": {
    "root_type": "map_scalar",
    "lua_shape": "[journal_instance_id] = map_id",
    "key_field": "journal_instance_id",
    "value_field": "map_id",
    "comment_field": "comment_name",
    "fields": []
  },
  "validation": {
    "required_fields": ["journal_instance_id", "map_id"],
    "unique_keys": ["journal_instance_id"],
    "non_null_fields": ["journal_instance_id", "map_id"],
    "sort_rules": [{"field": "journal_instance_id", "direction": "asc"}]
  },
  "versioning": {
    "current_schema_version": 1,
    "change_log": [{"schema_version": 1, "summary": "初始契约版本"}]
  }
}
```

Match the other two contracts to the locked IDs and root types above.

- [ ] **Step 4: Re-run the validator to verify it passes**

Run: `python tests/validate_data_contracts.py`

Expected: PASS with an `OK` message covering all three contracts

- [ ] **Step 5: Commit the plugin-side contract source files**

```bash
git add DataContracts/instance_map_ids.json DataContracts/instance_drops_mount.json DataContracts/instance_questlines.json tests/validate_data_contracts.py
git commit -m "功能: 增加 Toolbox 数据导出契约源" -m "- [功能] contracts: 新增 instance_map_ids / instance_drops_mount / instance_questlines 契约文件\n- [测试] contract validator: 增加插件侧契约静态校验脚本\n- 影响: 仅建立契约源，不改当前导出结果"
```

### Task 2: Wire the contract validator into the plugin test entrypoint

**Files:**
- Modify: `tests/run_all.py`

- [ ] **Step 1: Insert the new validator as the first static check**

Add a new `run_step(...)` call before `validate_settings_subcategories`:

```python
contract_ret = run_step(
    "validate_data_contracts",
    [sys.executable, "tests/validate_data_contracts.py"],
)
if contract_ret != 0:
    return contract_ret
```

- [ ] **Step 2: Run the validator and static tests**

Run: `python tests/validate_data_contracts.py`

Expected: PASS

Run: `python tests/validate_settings_subcategories.py`

Expected: PASS before any header migration work starts

- [ ] **Step 3: Run the aggregated Python entrypoint**

Run: `python tests/run_all.py --ci`

Expected: the contract validator passes first; if `busted` is unavailable locally, the command may stop later with the existing `busted not found` error, which is acceptable at this stage

- [ ] **Step 4: Commit the test entrypoint wiring**

```bash
git add tests/run_all.py
git commit -m "测试: 接入数据契约静态校验入口" -m "- [测试] run_all: 在现有静态校验前增加 validate_data_contracts\n- 影响: 先校验 DataContracts，再进入旧的结构校验"
```

## Chunk 2: WoWTools Contract Runtime

### Task 3: Write failing WoWTools unit tests for contract parsing and snapshots

**Files:**
- Create: `../WoWTools/scripts/export/contract_model.py`
- Create: `../WoWTools/scripts/export/contract_io.py`
- Create: `../WoWTools/scripts/export/tests/test_contract_model.py`
- Create: `../WoWTools/scripts/export/tests/test_contract_io.py`

- [ ] **Step 1: Write failing unit tests for contract parsing**

Cover at least:

- valid contract JSON loads into a typed object
- file name and `contract_id` mismatch raises
- missing required sections raises
- `versioning.current_schema_version` mismatch raises

Use temporary JSON fixtures inside the tests rather than reading live contracts directly.

- [ ] **Step 2: Write failing unit tests for snapshot writing**

Cover at least:

- snapshots land under `outputs/toolbox/contract_snapshots/<contract_id>/`
- file name format is `<contract_id>__schema_v<schema_version>__<timestamp>.json`
- snapshot contents are byte-for-byte JSON copies of the source contract

- [ ] **Step 3: Run the WoWTools unit tests to verify they fail**

Run from `D:\WoWProject\WoWTools`:

```bash
python -m unittest scripts.export.tests.test_contract_model scripts.export.tests.test_contract_io -v
```

Expected: FAIL because the loader/model modules do not exist yet

- [ ] **Step 4: Implement `contract_model.py` and `contract_io.py`**

`contract_model.py` should provide:

- dataclasses or typed dictionaries for the `contract/output/source/structure/validation/versioning` sections
- one validation function that enforces the spec rules already written in `2026-04-11-toolbox-data-contract-export-design.md`

`contract_io.py` should provide:

- default contract dir resolution pointing at `../WoWPlugin/DataContracts` from the `WoWTools` root
- `load_contract(contract_id, contract_dir)`
- `iter_active_contracts(contract_dir)`
- `write_contract_snapshot(contract, source_path, snapshots_root, timestamp)`

Make `contract_dir` and `snapshots_root` overridable via CLI args later; do not hardcode local machine paths.

- [ ] **Step 5: Re-run the WoWTools unit tests to verify they pass**

Run from `D:\WoWProject\WoWTools`:

```bash
python -m unittest scripts.export.tests.test_contract_model scripts.export.tests.test_contract_io -v
```

Expected: PASS

- [ ] **Step 6: Checkpoint the non-git WoWTools changes**

Because `../WoWTools` is not a git repository in this workspace, do not fabricate a commit. Instead:

- record the passing command output in the terminal history
- keep the touched file list explicit in the implementation notes

### Task 4: Write failing unit tests for tagged headers and fixed root-type writers

**Files:**
- Create: `../WoWTools/scripts/export/lua_contract_writer.py`
- Create: `../WoWTools/scripts/export/tests/test_lua_contract_writer.py`

- [ ] **Step 1: Write failing unit tests for header generation**

Assert that the writer emits this exact metadata block shape:

```lua
--[[
@contract_id instance_map_ids
@schema_version 1
@contract_file WoWPlugin/DataContracts/instance_map_ids.json
@contract_snapshot ...
@generated_at ...
@generated_by ...
@data_source wow.db
@summary ...
@overwrite_notice 此文件由工具生成，手改会被覆盖
]]
```

- [ ] **Step 2: Write failing unit tests for the three required root types**

Cover:

- `map_scalar` for `instance_map_ids`
- `map_array` for `instance_drops_mount`
- `document` for `instance_questlines`

Use standardized SQL alias fields in the test rows; do not couple tests to raw table column names.

- [ ] **Step 3: Run the writer tests to verify they fail**

Run from `D:\WoWProject\WoWTools`:

```bash
python -m unittest scripts.export.tests.test_lua_contract_writer -v
```

Expected: FAIL because `lua_contract_writer.py` does not exist yet

- [ ] **Step 4: Implement `lua_contract_writer.py`**

Provide:

- a header builder
- a post-write header parser for validation
- fixed writers for `map_scalar`, `map_array`, and `document`
- one dispatcher keyed by `structure.root_type`

Do not reintroduce per-target hard-coded renderers in the new contract runtime.

- [ ] **Step 5: Re-run the writer tests to verify they pass**

Run from `D:\WoWProject\WoWTools`:

```bash
python -m unittest scripts.export.tests.test_lua_contract_writer -v
```

Expected: PASS

- [ ] **Step 6: Checkpoint the non-git WoWTools changes**

Repeat the same checkpoint rule: save passing test evidence, do not invent a git commit.

### Task 5: Replace the hard-coded export registry with contract-driven orchestration

**Files:**
- Modify: `../WoWTools/scripts/export/toolbox_db_export.py`
- Modify: `../WoWTools/scripts/export/export_toolbox_all.py`
- Modify: `../WoWTools/scripts/export/export_toolbox_one.py`

- [ ] **Step 1: Write a failing integration test around single-contract export**

Add or extend a WoWTools test that:

- builds a temporary SQLite DB with the minimum rows for `instance_map_ids`
- points the exporter at a temporary `DataContracts` directory
- runs single-contract export
- asserts the output file contains the tagged header and the expected Lua root table

- [ ] **Step 2: Run the integration test to verify it fails**

Run from `D:\WoWProject\WoWTools`:

```bash
python -m unittest scripts.export.tests.test_contract_io scripts.export.tests.test_lua_contract_writer -v
```

Expected: FAIL in the export orchestration path because `toolbox_db_export.py` still depends on `RULES`

- [ ] **Step 3: Refactor `toolbox_db_export.py` to use contracts**

Required changes:

- remove the hard-coded `RULES` registry after the new runtime is in place
- load contracts from `contract_dir`
- execute `source.sql`
- validate result aliases against `structure` and `validation`
- render Lua through `lua_contract_writer`
- write the contract snapshot before or alongside the target Lua file
- preserve newline normalization (`\n`) and deterministic ordering

- [ ] **Step 4: Update the CLI entrypoints**

`export_toolbox_one.py`:

- primary selector must be `contract_id`
- keep output-file fallback only if the new tests need backward compatibility; otherwise remove it to simplify the interface
- add `--contract-dir` and `--snapshot-dir`

`export_toolbox_all.py`:

- enumerate `active` contracts from `contract_dir`
- stop using Lua file headers to discover export targets
- add `--contract-dir` and `--snapshot-dir`

- [ ] **Step 5: Re-run WoWTools unit tests plus a real single-contract export**

Run from `D:\WoWProject\WoWTools`:

```bash
python -m unittest discover -s scripts/export/tests -p "test_*.py"
python scripts/export/export_toolbox_one.py instance_map_ids --db data/sqlite/wow.db --contract-dir ..\WoWPlugin\DataContracts --data-dir ..\WoWPlugin\Toolbox\Data
```

Expected:

- unit tests PASS
- single-contract export prints an `[OK]` or `[DONE]` line and writes `..\WoWPlugin\Toolbox\Data\InstanceMapIDs.lua`

- [ ] **Step 6: Checkpoint the non-git WoWTools changes**

Record the passing commands and touched files; no fake commit.

## Chunk 3: Migration, Header Alignment, And Docs

### Task 6: Add failing plugin-side header alignment checks and regenerate the three data files

**Files:**
- Modify: `tests/validate_data_contracts.py`
- Modify: `tests/validate_settings_subcategories.py`
- Modify: `Toolbox/Data/InstanceMapIDs.lua`
- Modify: `Toolbox/Data/InstanceDrops_Mount.lua`
- Modify: `Toolbox/Data/InstanceQuestlines.lua`

- [ ] **Step 1: Extend the plugin validators to require tagged headers**

Add checks for each generated file:

- `@contract_id`
- `@schema_version`
- `@contract_file`
- `@contract_snapshot`
- `@generated_at`
- `@generated_by`
- `@data_source`

Also assert:

- `InstanceMapIDs.lua` -> `instance_map_ids`
- `InstanceDrops_Mount.lua` -> `instance_drops_mount`
- `InstanceQuestlines.lua` -> `instance_questlines`

- [ ] **Step 2: Run the plugin validators to verify they fail on the old headers**

Run from `D:\WoWProject\WoWPlugin`:

```bash
python tests/validate_data_contracts.py
python tests/validate_settings_subcategories.py
```

Expected: FAIL because the current generated Lua files still use the old free-form header format

- [ ] **Step 3: Regenerate all three data files through the new contract runtime**

Run from `D:\WoWProject\WoWTools`:

```bash
python scripts/export/export_toolbox_one.py instance_map_ids --db data/sqlite/wow.db --contract-dir ..\WoWPlugin\DataContracts --data-dir ..\WoWPlugin\Toolbox\Data
python scripts/export/export_toolbox_one.py instance_drops_mount --db data/sqlite/wow.db --contract-dir ..\WoWPlugin\DataContracts --data-dir ..\WoWPlugin\Toolbox\Data
python scripts/export/export_toolbox_one.py instance_questlines --db data/sqlite/wow.db --contract-dir ..\WoWPlugin\DataContracts --data-dir ..\WoWPlugin\Toolbox\Data
```

Expected: all three commands succeed and snapshots are written under `outputs/toolbox/contract_snapshots/`

- [ ] **Step 4: Re-run the plugin validators to verify they pass**

Run from `D:\WoWProject\WoWPlugin`:

```bash
python tests/validate_data_contracts.py
python tests/validate_settings_subcategories.py
```

Expected: PASS

- [ ] **Step 5: Commit the plugin-side contract migration artifacts**

```bash
git add tests/validate_data_contracts.py tests/validate_settings_subcategories.py Toolbox/Data/InstanceMapIDs.lua Toolbox/Data/InstanceDrops_Mount.lua Toolbox/Data/InstanceQuestlines.lua
git commit -m "功能: 迁移 Toolbox 数据文件到契约导出头" -m "- [功能] data exports: 用 contract_id/schema_version 标记三个现有生成数据文件\n- [测试] validators: 增加 Lua 文件头与契约对齐校验\n- 影响: 仅调整导出元数据和生成链路，不改插件运行时消费入口"
```

### Task 7: Update docs and stale rules after the migration is real

**Files:**
- Modify: `AGENTS.md`
- Modify: `README.md`
- Modify: `../WoWTools/README.md`

- [ ] **Step 1: Update `AGENTS.md` to reflect the new source of truth**

Replace the old header-driven wording in the export section with:

- `WoWPlugin/DataContracts/<contract_id>.json` is the single source of truth
- `Toolbox/Data/*.lua` headers reference contracts but do not define them
- `WoWTools` must export from contracts and save snapshots

Remove the stale special-case statement that says `InstanceQuestlines.lua` must stay outside automated export **only after** the new contract-based export path is working for that file.

- [ ] **Step 2: Update the user-facing READMEs**

`README.md`:

- add `DataContracts/` to the plugin-side directory overview
- explain that database-generated static data is now declared in JSON contracts

`../WoWTools/README.md`:

- replace “scan Lua headers to decide what to export” with “load active contracts from WoWPlugin/DataContracts”
- document `--contract-dir`
- document snapshot output path

- [ ] **Step 3: Run the full verification suite**

Run from `D:\WoWProject\WoWTools`:

```bash
python -m unittest discover -s scripts/export/tests -p "test_*.py"
python scripts/export/export_toolbox_all.py --db data/sqlite/wow.db --contract-dir ..\WoWPlugin\DataContracts --data-dir ..\WoWPlugin\Toolbox\Data
```

Expected: PASS and `[DONE]` output covering all active contracts

Run from `D:\WoWProject\WoWPlugin`:

```bash
python tests/validate_data_contracts.py
python tests/validate_settings_subcategories.py
python tests/run_all.py
```

Expected:

- Python validators PASS
- `tests/run_all.py` passes fully if `busted` is installed; otherwise report the existing environment blocker explicitly

- [ ] **Step 4: Commit the final plugin-side docs and verification-related changes**

```bash
git add AGENTS.md README.md docs/superpowers/plans/2026-04-11-toolbox-data-contract-export-implementation-plan.md
git commit -m "文档: 对齐契约驱动的数据导出流程" -m "- [文档] AGENTS: 将静态数据导出规则改为 DataContracts 驱动\n- [文档] README: 记录 WoWPlugin/DataContracts 和新的导出流程\n- [文档] plan: 保留本次实现计划作为后续执行基线\n- 影响: 仅更新文档和流程说明"
```

## Verification Summary

### WoWPlugin

- `python tests/validate_data_contracts.py`
- `python tests/validate_settings_subcategories.py`
- `python tests/run_all.py`

### WoWTools

- `python -m unittest discover -s scripts/export/tests -p "test_*.py"`
- `python scripts/export/export_toolbox_one.py instance_map_ids --db data/sqlite/wow.db --contract-dir ..\WoWPlugin\DataContracts --data-dir ..\WoWPlugin\Toolbox\Data`
- `python scripts/export/export_toolbox_all.py --db data/sqlite/wow.db --contract-dir ..\WoWPlugin\DataContracts --data-dir ..\WoWPlugin\Toolbox\Data`

## Done Definition

- `WoWPlugin/DataContracts/` contains valid contracts for the three current generated data files
- `WoWTools` no longer depends on the old hard-coded export registry for those files
- generated Lua files carry tagged contract headers
- immutable snapshots are written for each export
- plugin-side validators catch contract/header drift
- docs no longer describe the old header-discovery workflow
