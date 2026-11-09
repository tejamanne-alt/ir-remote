/// LAN-only address policy for hubs.
///
/// The app may only talk to hubs on the local network (build contract,
/// "Forbidden": runtime network calls other than LAN hubs, the pinned code-DB
/// CDN and opt-in crash reporting). Every hub address (typed, discovered or
/// restored from a backup) must pass [isLanHost] before any socket opens.
library;

import 'dart:io';

/// Whether [host] is a local-network address: an RFC 1918 or link-local
/// IPv4 address, an IPv6 link-local or unique-local address, loopback, or a
/// multicast-DNS `.local` name.
bool isLanHost(String host) {
  final h = host.trim().toLowerCase();
  if (h.isEmpty || h.length > 253) return false;
  if (h.endsWith('.local') &&
      RegExp(r'^[a-z0-9-]+(\.[a-z0-9-]+)*$').hasMatch(h)) {
    return true;
  }
  final addr = InternetAddress.tryParse(h);
  if (addr == null) return false;
  if (addr.isLoopback || addr.isLinkLocal) return true;
  final b = addr.rawAddress;
  if (addr.type == InternetAddressType.IPv4) {
    return b[0] == 10 ||
        (b[0] == 172 && b[1] >= 16 && b[1] <= 31) ||
        (b[0] == 192 && b[1] == 168);
  }
  if (addr.type == InternetAddressType.IPv6) {
    return (b[0] & 0xFE) == 0xFC; // fc00::/7 unique local
  }
  return false;
}
