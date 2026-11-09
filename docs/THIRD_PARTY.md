# Third-party components

Every dependency, data source and protocol reference used by this repository,
with its license. Gate L5 (`dart run check_licenses`) fails CI if a resolved
Dart package is missing below or its license differs. Allowed without asking:
MIT, BSD, Apache-2.0, ISC, Zlib, CC0. Anything else is listed in
`OPEN_QUESTIONS.md`, and may appear here only when it never ships in a mobile
binary (marked "not shipped").

## L4 human actions

- irdb announcement issue: _not opened yet_. No build containing irdb data,
  including betas, until the link is recorded on this line as
  `irdb announcement issue: https://github.com/probonopd/irdb/issues/<n>`.
  `tools/db_build` reads it.

## IR code data sources

| Source | Pinned commit | License (verified) | Used | Required notice |
| --- | --- | --- | --- | --- |
| [flipperdevices/irdb](https://github.com/flipperdevices/irdb) | `f7b15366521cc81ba11b341538f0097bddbb748b` | see code_db build report | bundled code sets | per its LICENSE |
| [probonopd/irdb](https://github.com/probonopd/irdb) | `11aa5eb3ad9fec9e5c03f170c29c1467733d9f3e` | irdb License (custom, conditions) | excluded until L4 is met | "Contains/accesses irdb by Simon Peter and contributors, used under permission. For licensing details and for information on how to contribute to the database, see https://github.com/probonopd/irdb" |
| [UberGuidoZ/Flipper-IRDB](https://github.com/UberGuidoZ/Flipper-IRDB) | n/a | CC0 only for later contributions | excluded in v1 (OPEN_QUESTIONS Q5) | n/a |
| User captures | n/a | user-owned | stay on the device | n/a |

## Protocol references (no code copied)

| Reference | License | What it specifies | Used in |
| --- | --- | --- | --- |
| SB-Projects IR knowledge base | public documentation | NEC, Sony SIRC, RC5, RC6, JVC, Sharp, Kaseikyo timing | `packages/ir_core/lib/src/codecs/` |
| JP1/hifi-remote DecodeIR protocol list (IRP notation) | public documentation | IRP definitions used by the codecs and by `tools/fixtures/irp_oracle.py` | codecs, golden fixtures |
| Philips "Pronto IR Formats"; Remote Central Pronto notes | public documentation | Pronto Hex 0000/5000/6000 | `formats/pronto.dart` |
| [Arduino-IRremote](https://github.com/Arduino-IRremote/Arduino-IRremote) `src/ir_LG.hpp` notes | MIT | LG 28-bit timing and checksum | `codecs/lg.dart` |
| [python-broadlink](https://github.com/mjg59/python-broadlink) @`730853e`, [DAB-LABS fork](https://github.com/DAB-LABS/python-broadlink) @`6c6567d` | MIT (© 2014 Mike Ryan, © 2016 Matthew Garrett) | Broadlink frame layout, checksum, AES key/IV, command codes, IR unit 8192/269 µs | `packages/ir_transports/lib/src/broadlink/` |

## Firmware (separate binary, own LICENSE)

See `firmware/esp32_bridge/README.md` ("Third-party"). IRremoteESP8266 is
LGPL-2.1: it is linked only into the bridge firmware, never into the app
(gate L2), and firmware source is published with every bridge release.

## Dart packages

| Package | License | Use |
| --- | --- | --- |
| `_fe_analyzer_shared` | BSD-3-Clause | transitive or dev |
| `analyzer` | BSD-3-Clause | transitive or dev |
| `args` | BSD-3-Clause | direct |
| `async` | BSD-3-Clause | transitive or dev |
| `bonsoir` | MIT | direct |
| `bonsoir_android` | MIT | transitive or dev |
| `bonsoir_darwin` | MIT | transitive or dev |
| `bonsoir_linux` | MIT | transitive or dev |
| `bonsoir_platform_interface` | MIT | transitive or dev |
| `bonsoir_windows` | MIT | transitive or dev |
| `boolean_selector` | BSD-3-Clause | transitive or dev |
| `build` | BSD-3-Clause | transitive or dev |
| `build_config` | BSD-3-Clause | transitive or dev |
| `build_daemon` | BSD-3-Clause | transitive or dev |
| `build_runner` | BSD-3-Clause | transitive or dev |
| `built_collection` | BSD-3-Clause | transitive or dev |
| `built_value` | BSD-3-Clause | transitive or dev |
| `characters` | BSD-3-Clause | transitive or dev |
| `charcode` | BSD-3-Clause | transitive or dev |
| `checked_yaml` | BSD-3-Clause | transitive or dev |
| `cli_config` | BSD-3-Clause | transitive or dev |
| `cli_util` | BSD-3-Clause | transitive or dev |
| `clock` | Apache-2.0 | transitive or dev |
| `code_assets` | BSD-3-Clause | transitive or dev |
| `collection` | BSD-3-Clause | transitive or dev |
| `convert` | BSD-3-Clause | transitive or dev |
| `coverage` | BSD-3-Clause | transitive or dev |
| `cross_file` | BSD-3-Clause | transitive or dev |
| `crypto` | BSD-3-Clause | direct |
| `dart_style` | BSD-3-Clause | transitive or dev |
| `dbus` | MPL-2.0 | not shipped (Linux desktop only, via bonsoir_linux); OPEN_QUESTIONS Q4 |
| `drift` | MIT | direct |
| `drift_dev` | MIT | transitive or dev |
| `drift_flutter` | MIT | direct |
| `fake_async` | Apache-2.0 | transitive or dev |
| `ffi` | BSD-3-Clause | transitive or dev |
| `ffi_leak_tracker` | BSD-3-Clause | transitive or dev |
| `file` | BSD-3-Clause | transitive or dev |
| `file_selector` | BSD-3-Clause | direct |
| `file_selector_android` | Apache-2.0 | transitive or dev |
| `file_selector_ios` | BSD-3-Clause | transitive or dev |
| `file_selector_linux` | BSD-3-Clause | transitive or dev |
| `file_selector_macos` | BSD-3-Clause | transitive or dev |
| `file_selector_platform_interface` | BSD-3-Clause | transitive or dev |
| `file_selector_web` | BSD-3-Clause | transitive or dev |
| `file_selector_windows` | BSD-3-Clause | transitive or dev |
| `fixnum` | BSD-3-Clause | transitive or dev |
| `flutter` | BSD-3-Clause | direct |
| `flutter_driver` | BSD-3-Clause | transitive or dev |
| `flutter_lints` | BSD-3-Clause | transitive or dev |
| `flutter_localizations` | BSD-3-Clause | direct |
| `flutter_test` | BSD-3-Clause | transitive or dev |
| `flutter_web_plugins` | BSD-3-Clause | transitive or dev |
| `frontend_server_client` | BSD-3-Clause | transitive or dev |
| `fuchsia_remote_debug_protocol` | BSD-3-Clause | transitive or dev |
| `glob` | BSD-3-Clause | transitive or dev |
| `graphs` | BSD-3-Clause | transitive or dev |
| `hooks` | BSD-3-Clause | transitive or dev |
| `http` | BSD-3-Clause | transitive or dev |
| `http_multi_server` | BSD-3-Clause | transitive or dev |
| `http_parser` | BSD-3-Clause | transitive or dev |
| `integration_test` | BSD-3-Clause | transitive or dev |
| `intl` | BSD-3-Clause | direct |
| `io` | BSD-3-Clause | transitive or dev |
| `jni` | BSD-3-Clause | transitive or dev |
| `jni_flutter` | BSD-3-Clause | transitive or dev |
| `jni_util` | BSD-3-Clause | transitive or dev |
| `json_annotation` | BSD-3-Clause | transitive or dev |
| `leak_tracker` | BSD-3-Clause | transitive or dev |
| `leak_tracker_flutter_testing` | BSD-3-Clause | transitive or dev |
| `leak_tracker_testing` | BSD-3-Clause | transitive or dev |
| `lints` | BSD-3-Clause | transitive or dev |
| `logging` | BSD-3-Clause | transitive or dev |
| `matcher` | BSD-3-Clause | transitive or dev |
| `material_color_utilities` | Apache-2.0 | transitive or dev |
| `meta` | BSD-3-Clause | transitive or dev |
| `mime` | BSD-3-Clause | transitive or dev |
| `native_toolchain_c` | BSD-3-Clause | transitive or dev |
| `node_preamble` | BSD-3-Clause | transitive or dev |
| `objective_c` | BSD-3-Clause | transitive or dev |
| `package_config` | BSD-3-Clause | transitive or dev |
| `path` | BSD-3-Clause | direct |
| `path_provider` | BSD-3-Clause | direct |
| `path_provider_android` | BSD-3-Clause | transitive or dev |
| `path_provider_foundation` | BSD-3-Clause | transitive or dev |
| `path_provider_linux` | BSD-3-Clause | transitive or dev |
| `path_provider_platform_interface` | BSD-3-Clause | transitive or dev |
| `path_provider_windows` | BSD-3-Clause | transitive or dev |
| `petitparser` | MIT | transitive or dev |
| `platform` | BSD-3-Clause | transitive or dev |
| `plugin_platform_interface` | BSD-3-Clause | transitive or dev |
| `pointycastle` | MIT | direct |
| `pool` | BSD-3-Clause | transitive or dev |
| `process` | BSD-3-Clause | transitive or dev |
| `pub_semver` | BSD-3-Clause | transitive or dev |
| `pubspec_parse` | BSD-3-Clause | transitive or dev |
| `recase` | BSD-2-Clause | transitive or dev |
| `record_use` | BSD-3-Clause | transitive or dev |
| `share_plus` | BSD-3-Clause | direct |
| `share_plus_platform_interface` | BSD-3-Clause | transitive or dev |
| `shelf` | BSD-3-Clause | transitive or dev |
| `shelf_packages_handler` | BSD-3-Clause | transitive or dev |
| `shelf_static` | BSD-3-Clause | transitive or dev |
| `shelf_web_socket` | BSD-3-Clause | transitive or dev |
| `sky_engine` | BSD-3-Clause | transitive or dev |
| `source_gen` | BSD-3-Clause | transitive or dev |
| `source_map_stack_trace` | BSD-3-Clause | transitive or dev |
| `source_maps` | BSD-3-Clause | transitive or dev |
| `source_span` | BSD-3-Clause | transitive or dev |
| `sqlcipher_flutter_libs` | Apache-2.0 | transitive or dev |
| `sqlite3` | MIT | direct |
| `sqlite3_flutter_libs` | MIT | transitive or dev |
| `sqlparser` | MIT | transitive or dev |
| `stack_trace` | BSD-3-Clause | transitive or dev |
| `stream_channel` | BSD-3-Clause | transitive or dev |
| `stream_transform` | BSD-3-Clause | transitive or dev |
| `string_scanner` | BSD-3-Clause | transitive or dev |
| `sync_http` | BSD-3-Clause | transitive or dev |
| `term_glyph` | BSD-3-Clause | transitive or dev |
| `test` | BSD-3-Clause | transitive or dev |
| `test_api` | BSD-3-Clause | transitive or dev |
| `test_core` | BSD-3-Clause | transitive or dev |
| `typed_data` | BSD-3-Clause | transitive or dev |
| `url_launcher_linux` | BSD-3-Clause | transitive or dev |
| `url_launcher_platform_interface` | BSD-3-Clause | transitive or dev |
| `url_launcher_web` | BSD-3-Clause | transitive or dev |
| `url_launcher_windows` | BSD-3-Clause | transitive or dev |
| `uuid` | MIT | transitive or dev |
| `vector_math` | BSD-3-Clause | transitive or dev |
| `vm_service` | BSD-3-Clause | transitive or dev |
| `watcher` | BSD-3-Clause | transitive or dev |
| `web` | BSD-3-Clause | transitive or dev |
| `web_socket` | BSD-3-Clause | transitive or dev |
| `web_socket_channel` | BSD-3-Clause | transitive or dev |
| `webdriver` | Apache-2.0 | transitive or dev |
| `webkit_inspection_protocol` | BSD-3-Clause | transitive or dev |
| `win32` | BSD-3-Clause | transitive or dev |
| `xdg_directories` | BSD-3-Clause | transitive or dev |
| `xml` | MIT | transitive or dev |
| `yaml` | MIT | transitive or dev |
| `yaml_edit` | BSD-3-Clause | transitive or dev |
