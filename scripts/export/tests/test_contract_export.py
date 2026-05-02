from __future__ import annotations

import json
import sqlite3
import tempfile
import unittest
from unittest import mock
from pathlib import Path

from scripts.export import toolbox_db_export
from scripts.export.toolbox_db_export import export_targets


def build_contract() -> dict:
    return {
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
            "write_header": True
        },
        "source": {
            "database": "wow.db",
            "tables": ["journalinstance"],
            "sql": "SELECT CAST(ID AS INTEGER) AS journal_instance_id, CAST(MapID AS INTEGER) AS map_id, Name_lang AS comment_name FROM journalinstance ORDER BY CAST(ID AS INTEGER)",
            "query": {
                "from": "journalinstance",
                "joins": [],
                "select": ["journal_instance_id", "map_id", "comment_name"],
                "where": [],
                "group_by": [],
                "order_by": ["journal_instance_id ASC"],
                "row_granularity": "一行代表一个副本映射"
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
            "unique_keys": [["journal_instance_id"]],
            "non_null_fields": ["journal_instance_id", "map_id"],
            "sort_rules": [{"field": "journal_instance_id", "direction": "asc"}]
        },
        "versioning": {
            "current_schema_version": 1,
            "change_log": [{"schema_version": 1, "summary": "初始契约版本"}]
        }
    }


def build_dataset_contract(dataset_sql: str) -> dict:
    return {
        "contract": {
            "contract_id": "instance_questlines",
            "schema_version": 1,
            "summary": "测试 datasets 校验路径",
            "source_of_truth": "WoWPlugin",
            "status": "active",
        },
        "output": {
            "lua_file": "Toolbox/Data/InstanceQuestlines.lua",
            "lua_table": "Toolbox.Data.InstanceQuestlines",
            "write_header": True,
        },
        "source": {
            "database": "wow.db",
            "tables": [],
            "sql": "SELECT 1 AS placeholder",
            "query": {
                "from": "placeholder",
                "joins": [],
                "select": ["placeholder"],
                "where": [],
                "group_by": [],
                "order_by": [],
                "row_granularity": "占位查询",
            },
            "datasets": {
                "links": {
                    "sql": dataset_sql,
                    "query": {
                        "from": "links",
                        "joins": [],
                        "select": ["quest_line_id", "quest_id", "order_index"],
                        "where": [],
                        "group_by": [],
                        "order_by": [],
                        "row_granularity": "任务线链接",
                    },
                },
            },
        },
        "structure": {
            "root_type": "document",
            "lua_shape": "Toolbox.Data.InstanceQuestlines = { schemaVersion, sourceMode, generatedAt, questLineXQuest }",
            "fields": [],
            "document_blocks": [
                {
                    "name": "metadata",
                    "metadata": {
                        "schemaVersion": 1,
                        "sourceMode": "live",
                        "generatedAt": "@generated_at",
                    },
                },
                {
                    "name": "questLineXQuest",
                    "dataset": "links",
                    "block_type": "map_array_objects_grouped",
                    "key_field": "quest_line_id",
                    "required_fields": ["quest_line_id", "quest_id", "order_index"],
                    "dedupe_by": ["quest_line_id", "quest_id", "order_index"],
                    "sort_by": ["quest_line_id", "order_index", "quest_id"],
                    "value_template": {
                        "QuestID": "quest_id",
                        "OrderIndex": "order_index",
                    },
                },
            ],
        },
        "validation": {
            "required_fields": ["quest_line_id", "quest_id", "order_index"],
            "unique_keys": [["quest_line_id", "quest_id", "order_index"]],
            "non_null_fields": ["quest_line_id", "quest_id", "order_index"],
            "sort_rules": [
                {"field": "quest_line_id", "direction": "asc"},
                {"field": "order_index", "direction": "asc"},
                {"field": "quest_id", "direction": "asc"},
            ],
        },
        "versioning": {
            "current_schema_version": 1,
            "change_log": [{"schema_version": 1, "summary": "初始契约版本"}],
        },
    }


class ContractExportIntegrationTests(unittest.TestCase):
    def test_export_targets_writes_contract_tagged_lua_file(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir_name:
            temp_dir = Path(temp_dir_name)
            db_path = temp_dir / "wow.db"
            contracts_dir = temp_dir / "DataContracts"
            output_dir = temp_dir / "Toolbox" / "Data"
            snapshots_dir = temp_dir / "snapshots"
            contracts_dir.mkdir(parents=True, exist_ok=True)
            output_dir.mkdir(parents=True, exist_ok=True)

            contract_path = contracts_dir / "instance_map_ids.json"
            contract_path.write_text(json.dumps(build_contract(), ensure_ascii=False, indent=2), encoding="utf-8")

            sqlite_conn = sqlite3.connect(db_path)
            sqlite_conn.execute("CREATE TABLE journalinstance (ID TEXT, MapID TEXT, Name_lang TEXT)")
            sqlite_conn.execute("INSERT INTO journalinstance VALUES ('63', '36', 'Deadmines')")
            sqlite_conn.execute("INSERT INTO journalinstance VALUES ('64', '33', 'Shadowfang Keep')")
            sqlite_conn.commit()
            sqlite_conn.close()

            written_files = export_targets(
                target_ids=["instance_map_ids"],
                db_path=db_path,
                data_dir=output_dir,
                contract_dir=contracts_dir,
                snapshot_dir=snapshots_dir,
                generated_by="test-suite",
            )

            self.assertEqual(len(written_files), 1)
            output_path = output_dir / "InstanceMapIDs.lua"
            self.assertEqual(written_files[0], output_path)
            output_text = output_path.read_text(encoding="utf-8")
            self.assertIn("@contract_id instance_map_ids", output_text)
            self.assertIn("@schema_version 1", output_text)
            self.assertIn("Toolbox.Data.InstanceMapIDs = {", output_text)
            self.assertIn("[63] = 36, -- Deadmines", output_text)
            self.assertIn("[64] = 33, -- Shadowfang Keep", output_text)

    def test_export_targets_rejects_duplicate_rows_in_dataset_validation_path(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir_name:
            temp_dir = Path(temp_dir_name)
            db_path = temp_dir / "wow.db"
            contracts_dir = temp_dir / "DataContracts"
            output_dir = temp_dir / "Toolbox" / "Data"
            snapshots_dir = temp_dir / "snapshots"
            contracts_dir.mkdir(parents=True, exist_ok=True)
            output_dir.mkdir(parents=True, exist_ok=True)

            contract_path = contracts_dir / "instance_questlines.json"
            contract_path.write_text(
                json.dumps(
                    build_dataset_contract(
                        "SELECT 5531 AS quest_line_id, 84956 AS quest_id, 1 AS order_index "
                        "UNION ALL "
                        "SELECT 5531 AS quest_line_id, 84956 AS quest_id, 1 AS order_index"
                    ),
                    ensure_ascii=False,
                    indent=2,
                ),
                encoding="utf-8",
            )

            sqlite_conn = sqlite3.connect(db_path)
            sqlite_conn.close()

            with self.assertRaisesRegex(ValueError, "duplicate key group"):
                export_targets(
                    target_ids=["instance_questlines"],
                    db_path=db_path,
                    data_dir=output_dir,
                    contract_dir=contracts_dir,
                    snapshot_dir=snapshots_dir,
                    generated_by="test-suite",
                )

    def test_export_targets_rejects_null_rows_in_dataset_validation_path(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir_name:
            temp_dir = Path(temp_dir_name)
            db_path = temp_dir / "wow.db"
            contracts_dir = temp_dir / "DataContracts"
            output_dir = temp_dir / "Toolbox" / "Data"
            snapshots_dir = temp_dir / "snapshots"
            contracts_dir.mkdir(parents=True, exist_ok=True)
            output_dir.mkdir(parents=True, exist_ok=True)

            contract_path = contracts_dir / "instance_questlines.json"
            contract_path.write_text(
                json.dumps(
                    build_dataset_contract(
                        "SELECT 5531 AS quest_line_id, 84956 AS quest_id, NULL AS order_index"
                    ),
                    ensure_ascii=False,
                    indent=2,
                ),
                encoding="utf-8",
            )

            sqlite_conn = sqlite3.connect(db_path)
            sqlite_conn.close()

            with self.assertRaisesRegex(ValueError, "non-null field order_index is empty"):
                export_targets(
                    target_ids=["instance_questlines"],
                    db_path=db_path,
                    data_dir=output_dir,
                    contract_dir=contracts_dir,
                    snapshot_dir=snapshots_dir,
                    generated_by="test-suite",
                )


class NavigationWalkComponentExportTests(unittest.TestCase):
    def test_enrich_walk_components_derives_transport_landing_components_without_override_file(self) -> None:
        sqlite_conn = sqlite3.connect(":memory:")
        synthetic_route_nodes = [
            {
                "node_id": 83,
                "node_kind": "map_anchor",
                "route_source": "uimap",
                "source_id": 85,
                "ui_map_id": 85,
                "map_id": 1,
                "node_name": "奥格瑞玛",
                "walk_cluster_node_id": 83,
                "pos_x": None,
                "pos_y": None,
                "pos_z": None,
            },
            {
                "node_id": 3249,
                "node_kind": "transport",
                "route_source": "waypoint_transport",
                "source_id": 148,
                "ui_map_id": 85,
                "map_id": 1,
                "node_name": "乘坐奥格瑞玛的飞艇前往荆棘谷",
                "walk_cluster_node_id": 83,
                "pos_x": 1871.02,
                "pos_y": -4419.94,
                "pos_z": 135.233,
            },
            {
                "node_id": 3251,
                "node_kind": "transport",
                "route_source": "waypoint_transport",
                "source_id": 150,
                "ui_map_id": 85,
                "map_id": 1,
                "node_name": "乘坐奥格瑞玛的飞艇前往北风苔原",
                "walk_cluster_node_id": 83,
                "pos_x": 1764.4,
                "pos_y": -4285.97,
                "pos_z": 133.107,
            },
        ]
        synthetic_transport_rows = [
            {
                "waypoint_node_id": 148,
                "node_type": 0,
                "player_condition_id": 923,
            },
            {
                "waypoint_node_id": 150,
                "node_type": 0,
                "player_condition_id": 923,
            },
        ]

        with (
            mock.patch.object(
                toolbox_db_export,
                "build_navigation_walk_component_route_datasets",
                return_value={
                    "nodes": synthetic_route_nodes,
                    "transport_nodes_raw": synthetic_transport_rows,
                },
            ),
        ):
            datasets = toolbox_db_export.enrich_navigation_walk_component_datasets(
                sqlite_conn,
                {"seed": [{"placeholder": 1}]},
            )

        assignment_by_node_id = {
            int(assignment_row["node_id"]): assignment_row
            for assignment_row in datasets["node_assignments"]
        }
        component_ids = {
            component_row["component_id"]
            for component_row in datasets["components"]
        }

        self.assertIn(3249, assignment_by_node_id)
        self.assertIn(3251, assignment_by_node_id)
        self.assertTrue(any(component_id.endswith("_arrival_3249") for component_id in component_ids))
        self.assertTrue(any(component_id.endswith("_arrival_3251") for component_id in component_ids))
        self.assertNotIn("uimap_85_city", component_ids)

    def test_enrich_walk_components_hides_generic_arrival_portal_without_override_file(self) -> None:
        sqlite_conn = sqlite3.connect(":memory:")
        synthetic_route_nodes = [
            {
                "node_id": 2805,
                "node_kind": "portal",
                "route_source": "portal",
                "source_id": 101,
                "ui_map_id": 85,
                "map_id": 1,
                "node_name": "探路者大厅",
                "walk_cluster_node_id": 83,
                "pos_x": 1445.21,
                "pos_y": -4499.56,
                "pos_z": 18.3064,
            },
            {
                "node_id": 3198,
                "node_kind": "portal",
                "route_source": "portal",
                "source_id": 527,
                "ui_map_id": 85,
                "map_id": 1,
                "node_name": "通往奥格瑞玛的传送门",
                "walk_cluster_node_id": 83,
                "pos_x": 1445.21,
                "pos_y": -4499.56,
                "pos_z": 18.3067,
            },
        ]
        synthetic_portal_rows = [
            {
                "waypoint_node_id": 101,
                "node_type": 1,
                "player_condition_id": 0,
            },
            {
                "waypoint_node_id": 527,
                "node_type": 2,
                "player_condition_id": 0,
            },
        ]

        with (
            mock.patch.object(
                toolbox_db_export,
                "build_navigation_walk_component_route_datasets",
                return_value={
                    "nodes": synthetic_route_nodes,
                    "portal_nodes_raw": synthetic_portal_rows,
                },
            ),
        ):
            datasets = toolbox_db_export.enrich_navigation_walk_component_datasets(
                sqlite_conn,
                {"seed": [{"placeholder": 1}]},
            )

        assignment_by_node_id = {
            int(assignment_row["node_id"]): assignment_row
            for assignment_row in datasets["node_assignments"]
        }
        proxy_by_node_id = {
            int(proxy_row["node_id"]): proxy_row
            for proxy_row in datasets["display_proxies"]
        }
        technical_assignment = assignment_by_node_id[3198]
        proxy_row = proxy_by_node_id[3198]

        self.assertTrue(technical_assignment["hidden_in_semantic_chain"])
        self.assertEqual(technical_assignment["display_proxy_node_id"], 2805)
        self.assertEqual(proxy_row["display_proxy_node_id"], 2805)

    def test_enrich_walk_components_prefers_duplicate_name_anchor_with_real_local_support(self) -> None:
        sqlite_conn = sqlite3.connect(":memory:")
        synthetic_route_nodes = [
            {
                "node_id": 107,
                "node_kind": "map_anchor",
                "route_source": "uimap",
                "source_id": 110,
                "ui_map_id": 110,
                "map_id": 530,
                "node_name": "银月城",
                "walk_cluster_node_id": 92,
                "pos_x": None,
                "pos_y": None,
                "pos_z": None,
            },
            {
                "node_id": 1554,
                "node_kind": "map_anchor",
                "route_source": "uimap",
                "source_id": 2393,
                "ui_map_id": 2393,
                "map_id": 0,
                "node_name": "银月城",
                "walk_cluster_node_id": 1556,
                "pos_x": None,
                "pos_y": None,
                "pos_z": None,
            },
            {
                "node_id": 1583,
                "node_kind": "map_anchor",
                "route_source": "uimap",
                "source_id": 2443,
                "ui_map_id": 2443,
                "map_id": 2907,
                "node_name": "银月城",
                "walk_cluster_node_id": 1556,
                "pos_x": None,
                "pos_y": None,
                "pos_z": None,
            },
            {
                "node_id": 3172,
                "node_kind": "portal",
                "route_source": "portal",
                "source_id": 496,
                "ui_map_id": 2393,
                "map_id": 0,
                "node_name": "使用银月城的传送门前往奥格瑞玛",
                "walk_cluster_node_id": 1556,
                "pos_x": 1.0,
                "pos_y": 1.0,
                "pos_z": 0.0,
            },
            {
                "node_id": 3197,
                "node_kind": "portal",
                "route_source": "portal",
                "source_id": 526,
                "ui_map_id": 2393,
                "map_id": 0,
                "node_name": "通往银月城的传送门",
                "walk_cluster_node_id": 1556,
                "pos_x": 1.5,
                "pos_y": 1.0,
                "pos_z": 0.0,
            },
            {
                "node_id": 3200,
                "node_kind": "portal",
                "route_source": "portal",
                "source_id": 529,
                "ui_map_id": 2393,
                "map_id": 0,
                "node_name": "通往银月城的传送门",
                "walk_cluster_node_id": 1556,
                "pos_x": 2.0,
                "pos_y": 1.0,
                "pos_z": 0.0,
            },
            {
                "node_id": 2820,
                "node_kind": "portal",
                "route_source": "portal",
                "source_id": 116,
                "ui_map_id": 110,
                "map_id": 530,
                "node_name": "银月城",
                "walk_cluster_node_id": 92,
                "pos_x": 100.0,
                "pos_y": 100.0,
                "pos_z": 0.0,
            },
        ]
        synthetic_portal_rows = [
            {
                "waypoint_node_id": 496,
                "node_type": 1,
                "player_condition_id": 0,
            },
            {
                "waypoint_node_id": 526,
                "node_type": 2,
                "player_condition_id": 0,
            },
            {
                "waypoint_node_id": 529,
                "node_type": 2,
                "player_condition_id": 0,
            },
            {
                "waypoint_node_id": 116,
                "node_type": 2,
                "player_condition_id": 0,
            },
        ]

        with (
            mock.patch.object(
                toolbox_db_export,
                "build_navigation_walk_component_route_datasets",
                return_value={
                    "nodes": synthetic_route_nodes,
                    "portal_nodes_raw": synthetic_portal_rows,
                },
            ),
            mock.patch.object(
                toolbox_db_export,
                "query_navigation_walk_component_uimap_semantics",
                return_value={
                    110: {"ui_map_type": 3, "has_city_area_flag": False},
                    2393: {"ui_map_type": 3, "has_city_area_flag": True},
                    2443: {"ui_map_type": 3, "has_city_area_flag": False},
                },
            ),
        ):
            datasets = toolbox_db_export.enrich_navigation_walk_component_datasets(
                sqlite_conn,
                {"seed": [{"placeholder": 1}]},
            )

        component_rows = datasets["components"]
        matched_component = None
        for component_row in component_rows:
            if 3197 in component_row["member_node_ids"] or 3200 in component_row["member_node_ids"]:
                matched_component = component_row
                break

        self.assertIsNotNone(matched_component)
        self.assertEqual(1554, matched_component["preferred_anchor_node_id"])

    def test_enrich_walk_components_does_not_promote_single_arrival_portal_to_city_component(self) -> None:
        sqlite_conn = sqlite3.connect(":memory:")
        synthetic_route_nodes = [
            {
                "node_id": 500,
                "node_kind": "map_anchor",
                "route_source": "uimap",
                "source_id": 900,
                "ui_map_id": 900,
                "map_id": 1,
                "node_name": "普通区域",
                "walk_cluster_node_id": 500,
                "pos_x": None,
                "pos_y": None,
                "pos_z": None,
            },
            {
                "node_id": 501,
                "node_kind": "portal",
                "route_source": "portal",
                "source_id": 901,
                "ui_map_id": 900,
                "map_id": 1,
                "node_name": "通往普通区域的传送门",
                "walk_cluster_node_id": 500,
                "pos_x": 50.0,
                "pos_y": 50.0,
                "pos_z": 0.0,
            },
        ]
        synthetic_portal_rows = [
            {
                "waypoint_node_id": 501,
                "node_type": 2,
                "player_condition_id": 0,
            }
        ]

        with (
            mock.patch.object(
                toolbox_db_export,
                "build_navigation_walk_component_route_datasets",
                return_value={
                    "nodes": synthetic_route_nodes,
                    "portal_nodes_raw": synthetic_portal_rows,
                },
            ),
        ):
            datasets = toolbox_db_export.enrich_navigation_walk_component_datasets(
                sqlite_conn,
                {"seed": [{"placeholder": 1}]},
            )

        city_component_ids = {
            component_row["component_id"]
            for component_row in datasets["components"]
            if component_row["component_id"].endswith("_city")
        }

        self.assertNotIn("uimap_900_city", city_component_ids)

    def test_enrich_walk_components_does_not_promote_duplicate_name_arrival_only_cluster_to_city_component(self) -> None:
        sqlite_conn = sqlite3.connect(":memory:")
        synthetic_route_nodes = [
            {
                "node_id": 1000,
                "node_kind": "map_anchor",
                "route_source": "uimap",
                "source_id": 100,
                "ui_map_id": 100,
                "map_id": 1,
                "node_name": "测试城",
                "walk_cluster_node_id": 1000,
                "pos_x": None,
                "pos_y": None,
                "pos_z": None,
            },
            {
                "node_id": 1001,
                "node_kind": "map_anchor",
                "route_source": "uimap",
                "source_id": 101,
                "ui_map_id": 101,
                "map_id": 0,
                "node_name": "测试城",
                "walk_cluster_node_id": 1001,
                "pos_x": None,
                "pos_y": None,
                "pos_z": None,
            },
            {
                "node_id": 1100,
                "node_kind": "portal",
                "route_source": "portal",
                "source_id": 200,
                "ui_map_id": 100,
                "map_id": 1,
                "node_name": "通往测试城的传送门",
                "walk_cluster_node_id": 1000,
                "pos_x": 10.0,
                "pos_y": 10.0,
                "pos_z": 0.0,
            },
            {
                "node_id": 1101,
                "node_kind": "portal",
                "route_source": "portal",
                "source_id": 201,
                "ui_map_id": 101,
                "map_id": 0,
                "node_name": "通往测试城的传送门",
                "walk_cluster_node_id": 1001,
                "pos_x": 20.0,
                "pos_y": 20.0,
                "pos_z": 0.0,
            },
        ]
        synthetic_portal_rows = [
            {
                "waypoint_node_id": 200,
                "node_type": 2,
                "player_condition_id": 0,
            },
            {
                "waypoint_node_id": 201,
                "node_type": 2,
                "player_condition_id": 0,
            },
        ]

        with (
            mock.patch.object(
                toolbox_db_export,
                "build_navigation_walk_component_route_datasets",
                return_value={
                    "nodes": synthetic_route_nodes,
                    "portal_nodes_raw": synthetic_portal_rows,
                },
            ),
        ):
            datasets = toolbox_db_export.enrich_navigation_walk_component_datasets(
                sqlite_conn,
                {"seed": [{"placeholder": 1}]},
            )

        city_component_ids = {
            component_row["component_id"]
            for component_row in datasets["components"]
            if component_row["component_id"].endswith("_city")
        }

        self.assertNotIn("uimap_101_city", city_component_ids)

    def test_enrich_walk_components_requires_city_semantics_for_duplicate_name_city_fallback(self) -> None:
        sqlite_conn = sqlite3.connect(":memory:")
        synthetic_route_nodes = [
            {
                "node_id": 2000,
                "node_kind": "map_anchor",
                "route_source": "uimap",
                "source_id": 200,
                "ui_map_id": 200,
                "map_id": 1,
                "node_name": "测试枢纽",
                "walk_cluster_node_id": 2000,
                "pos_x": None,
                "pos_y": None,
                "pos_z": None,
            },
            {
                "node_id": 2001,
                "node_kind": "map_anchor",
                "route_source": "uimap",
                "source_id": 201,
                "ui_map_id": 201,
                "map_id": 0,
                "node_name": "测试枢纽",
                "walk_cluster_node_id": 2001,
                "pos_x": None,
                "pos_y": None,
                "pos_z": None,
            },
            {
                "node_id": 2100,
                "node_kind": "portal",
                "route_source": "portal",
                "source_id": 300,
                "ui_map_id": 201,
                "map_id": 0,
                "node_name": "使用测试枢纽的传送门前往主城",
                "walk_cluster_node_id": 2001,
                "pos_x": 1.0,
                "pos_y": 1.0,
                "pos_z": 0.0,
            },
            {
                "node_id": 2101,
                "node_kind": "portal",
                "route_source": "portal",
                "source_id": 301,
                "ui_map_id": 201,
                "map_id": 0,
                "node_name": "通往测试枢纽的传送门",
                "walk_cluster_node_id": 2001,
                "pos_x": 1.5,
                "pos_y": 1.0,
                "pos_z": 0.0,
            },
            {
                "node_id": 2102,
                "node_kind": "portal",
                "route_source": "portal",
                "source_id": 302,
                "ui_map_id": 201,
                "map_id": 0,
                "node_name": "通往测试枢纽的传送门",
                "walk_cluster_node_id": 2001,
                "pos_x": 2.0,
                "pos_y": 1.0,
                "pos_z": 0.0,
            },
        ]
        synthetic_portal_rows = [
            {
                "waypoint_node_id": 300,
                "node_type": 1,
                "player_condition_id": 0,
            },
            {
                "waypoint_node_id": 301,
                "node_type": 2,
                "player_condition_id": 0,
            },
            {
                "waypoint_node_id": 302,
                "node_type": 2,
                "player_condition_id": 0,
            },
        ]

        with (
            mock.patch.object(
                toolbox_db_export,
                "build_navigation_walk_component_route_datasets",
                return_value={
                    "nodes": synthetic_route_nodes,
                    "portal_nodes_raw": synthetic_portal_rows,
                },
            ),
            mock.patch.object(
                toolbox_db_export,
                "query_navigation_walk_component_uimap_semantics",
                return_value={
                    200: {"ui_map_type": 3, "has_city_area_flag": False},
                    201: {"ui_map_type": 3, "has_city_area_flag": False},
                },
            ),
        ):
            datasets = toolbox_db_export.enrich_navigation_walk_component_datasets(
                sqlite_conn,
                {"seed": [{"placeholder": 1}]},
            )

        city_component_ids = {
            component_row["component_id"]
            for component_row in datasets["components"]
            if component_row["component_id"].endswith("_city")
        }

        self.assertNotIn("uimap_201_city", city_component_ids)

if __name__ == "__main__":
    unittest.main()
