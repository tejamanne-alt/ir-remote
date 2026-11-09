import 'dart:io';

import 'package:db_build/db_build.dart';
import 'package:path/path.dart' as p;

/// The MIT licence as published by flipperdevices/irdb.
const String mitText = '''
MIT License

Copyright (c) Flipper Zero

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
''';

/// The conditions and notice of the irdb licence (excerpt with the parts
/// the verifier looks for).
const String irdbLicenseExcerpt = '''
# License

1. Prior to using this database in your product, you will inform the irdb
   project about your product by opening an issue on
   https://github.com/probonopd/irdb/issues

2. The following notice shall be included in your product:
   `Contains/accesses irdb by Simon Peter and contributors, used under permission.
   For licensing details and for information on how to contribute to the database, see
   https://github.com/probonopd/irdb`

3. You will make available up to three fully licensed copies/units of your product
   to the irdb team, represented by Simon Peter, free of charge
''';

const String _h = 'Filetype: IR signals file\nVersion: 1\n';

String _bytes(String s) {
  final parts = s.split(' ');
  while (parts.length < 4) {
    parts.add('00');
  }
  return parts.join(' ');
}

String _p(String name, String protocol, String a, String c) =>
    '#\nname: $name\ntype: parsed\nprotocol: $protocol\n'
    'address: ${_bytes(a)}\ncommand: ${_bytes(c)}\n';

String _r(String name, List<int> data, {int hz = 38000}) =>
    '#\nname: $name\ntype: raw\nfrequency: $hz\nduty_cycle: 0.330000\n'
    'data: ${data.join(' ')}\n';

const List<int> _rawMute = [9000, 4500, 560, 1690, 560, 560, 560];

List<int> _scaled(double f) => [for (final d in _rawMute) (d * f).round()];

void _write(String root, String rel, String text) {
  final f = File(p.join(root, rel));
  f.parent.createSync(recursive: true);
  f.writeAsStringSync(text);
}

/// Writes a small flipperdevices/irdb-shaped tree under [root].
void writeFlipperTree(String root) {
  const c = 'database/categories';
  _write(
    root,
    '$c/TVs/Samsung/Samsung_A/Samsung_A.ir',
    _h +
        _p('Power', 'Samsung32', '07', '02') +
        _p('Vol_up', 'Samsung32', '07', '07') +
        _p('Source', 'Samsung32', '07', '01') +
        _p('Exotic', 'NEC42', '1A', '17'),
  );
  _write(
    root,
    '$c/TVs/Samsung/Samsung_B/Samsung_B.ir',
    _h + _p('POWER', 'Samsung32', '07', '02'),
  );
  // Same content as Samsung_A under another spelling of the brand.
  _write(
    root,
    '$c/TVs/SAMSUNG/Samsung_C/Samsung_C.ir',
    _h +
        _p('Power', 'Samsung32', '07', '02') +
        _p('Vol_up', 'Samsung32', '07', '07') +
        _p('Source', 'Samsung32', '07', '01'),
  );
  _write(
    root,
    '$c/TVs/LG/LG_1/LG_1.ir',
    _h +
        _p('Power', 'NEC', '04', '08') +
        _r('Mute', _rawMute) +
        _p('Mute', 'NEC', '04', '09') + // clash: kept as custom:Mute
        _p('power', 'NEC', '04', '08'), // exact repeat: dropped
  );
  // Raw within 20% of LG_1's: a subset, merged.
  _write(
    root,
    '$c/TVs/LG/LG_2/LG_2.ir',
    _h + _p('Power', 'NEC', '04', '08') + _r('Mute', _scaled(1.2)),
  );
  // Raw 50% longer: not equivalent, kept; no power key, ranked last.
  _write(root, '$c/TVs/LG/LG_3/LG_3.ir', _h + _r('Mute', _scaled(1.5)));
  _write(
    root,
    '$c/TVs/LG/LG_4/LG_4.ir',
    _h + _p('Power', 'NEC', '04', '0C') + _p('Mute', 'NEC', '04', '0D'),
  );
  _write(
    root,
    '$c/DVD/Sony/Sony_D/Sony_D.ir',
    _h + _p('Power', 'SIRC', '01', '15'),
  );
  _write(
    root,
    '$c/Box/Tata_Sky/TS_1/TS_1.ir',
    _h +
        _p('Power', 'NECext', '80 7F', '0A F5') +
        _p('Guide', 'RC5X', '1F', '01'),
  );
  _write(
    root,
    '$c/Fan/Acme/Fan_1/Fan_1.ir',
    _h + _r('Power', [1200, 400, 1200, 400]) + _r('Wind', [400, 1200, 400]),
  );
  _write(
    root,
    '$c/Fan/Acme/Fan_1/config.json',
    '{"key_map": {"FAN_SPEED": {"type": "SHA_256", "key_name": "Wind"}}}',
  );
  _write(root, '$c/Fan/Acme/Broken/Broken.ir', 'not a flipper file\n');
  _write(root, '$c/Fan/Acme/Empty/Empty.ir', _h + _p('X', 'RCA', '0F', '54'));
  _write(root, '$c/Fan/stray.ir', _h + _p('Power', 'NEC', '01', '01'));
  _write(root, '$c/.meta/manifest.json', '{}');
}

/// Writes a small probonopd/irdb-shaped tree under [root].
void writeIrdbTree(String root) {
  const h = 'functionname,protocol,device,subdevice,function\n';
  _write(root, 'codes/Samsung/TV/7,7.csv', '${h}POWER,NECx2,7,7,2\n');
  _write(
    root,
    'codes/ONIDA/TV/0,-1.csv',
    '${h}POWER,RC5,0,-1,12\nMUTE,RC5,0,-1,13\nX,Pioneer,1,-1,1\n',
  );
  _write(root, 'codes/Foo/DVD Player/1,-1.csv', '${h}POWER,NEC1,1,-1,1\n');
}

/// A resolver serving [trees] (source name to directory) without git.
SourceResolver fakeResolver(
  Map<String, String> trees, {
  SourceSpec Function(SourceSpec)? patch,
}) =>
    (spec) => ResolvedSource(
      spec: patch == null ? spec : patch(spec),
      root: trees[spec.name]!,
      commitDate: spec.kind == SourceKind.flipper ? '2026-04-24' : '2026-01-14',
      notice: spec.kind == SourceKind.flipper
          ? mitText.trim()
          : irdbNotice(irdbLicenseExcerpt)!,
    );

/// [spec] with every field copied except those given.
SourceSpec copySpec(
  SourceSpec spec, {
  String? commit,
  String? licenseId,
  String? licenseSha256,
}) => SourceSpec(
  kind: spec.kind,
  name: spec.name,
  url: spec.url,
  cloneUrl: spec.cloneUrl,
  commit: commit ?? spec.commit,
  cacheName: spec.cacheName,
  licensePath: spec.licensePath,
  licenseId: licenseId ?? spec.licenseId,
  licenseSha256: licenseSha256 ?? spec.licenseSha256,
  priority: spec.priority,
);
