/// Brand names: ranking lists from the build contract and canonicalization.
library;

import 'package:code_db/code_db.dart';
import 'package:ir_core/ir_core.dart';

/// `{{TV_BRANDS_V1}}`: ranking order for TVs (India-first defaults).
const List<String> tvBrandsV1 = [
  'Samsung',
  'LG',
  'Sony',
  'Xiaomi',
  'OnePlus',
  'TCL',
  'Hisense',
  'Vu',
  'Panasonic',
  'Philips',
];

/// `{{STB_V1}}`: set-top boxes for the primary market.
const List<String> stbV1 = [
  'Tata Play',
  'Airtel Digital TV',
  'Dish TV',
  'd2h',
  'Sun Direct',
];

/// `{{AC_BRANDS_V1}}`: AC brand candidates; the human confirms the final
/// eight and their order before M5.
const List<String> acBrandsV1 = [
  'Voltas',
  'LG',
  'Samsung',
  'Daikin',
  'Blue Star',
  'Lloyd',
  'Panasonic',
  'Hitachi',
];

/// Primary-market ranking per category. Categories without a list in the
/// contract (fan, projector, soundbar, air purifier) list brands
/// alphabetically.
const Map<DeviceCategory, List<String>> primaryBrands = {
  DeviceCategory.tv: tvBrandsV1,
  DeviceCategory.setTopBox: stbV1,
  DeviceCategory.airConditioner: acBrandsV1,
};

/// Former names that refer to a ranked brand (search-key form). Tata Sky
/// was renamed Tata Play in January 2022.
const Map<String, String> brandAliases = {'tatasky': 'Tata Play'};

/// Picks one display name per brand across sources.
///
/// Source directory names are compared by their search key (lower case,
/// no spaces or punctuation, underscores read as spaces). A key that matches
/// a ranked brand, or an alias of one, takes the ranked spelling; otherwise
/// the most frequent spelling wins, ties broken alphabetically.
final class BrandCanonicalizer {
  final Map<String, Map<String, int>> _variants = {};

  static final Map<String, String> _ranked = {
    for (final list in primaryBrands.values)
      for (final b in list) brandSearchKey(b): b,
    for (final e in brandAliases.entries) e.key: e.value,
  };

  /// Display form of a directory name: underscores become spaces.
  static String display(String raw) =>
      raw.replaceAll('_', ' ').replaceAll(RegExp(r'\s+'), ' ').trim();

  /// The grouping key of [raw].
  static String keyOf(String raw) => brandSearchKey(display(raw));

  /// Records one occurrence of [raw].
  void add(String raw) {
    final v = _variants.putIfAbsent(keyOf(raw), () => {});
    final d = display(raw);
    v[d] = (v[d] ?? 0) + 1;
  }

  /// The canonical name for [raw]; [add] must have seen its key.
  String canonical(String raw) {
    final key = keyOf(raw);
    final ranked = _ranked[key];
    if (ranked != null) return ranked;
    final variants = _variants[key];
    if (variants == null || variants.isEmpty) return display(raw);
    final sorted = variants.entries.toList()
      ..sort((a, b) {
        final c = b.value.compareTo(a.value);
        return c != 0 ? c : a.key.compareTo(b.key);
      });
    return sorted.first.key;
  }
}
