/// How a trip stays the same on every phone.
///
/// In the cloud a trip is a tree of maps. To see what changed it is laid out
/// flat, one entry per value under its path (`offers/abc/votes/ana`). Everything
/// is compared and sent value by value, so two people changing different things
/// at the same moment never overwrite each other.
library;

typedef Tree = Map<String, dynamic>;

/// Path -> value. Only strings, numbers and booleans; an empty map or a null is
/// simply not there, as in the database.
typedef Flat = Map<String, Object>;

Flat flatten(Tree tree, [String prefix = '']) {
  final flat = <String, Object>{};
  tree.forEach((key, value) {
    final path = prefix.isEmpty ? key : '$prefix/$key';
    if (value is Map) {
      flat.addAll(flatten(value.cast<String, dynamic>(), path));
    } else if (value != null) {
      flat[path] = value as Object;
    }
  });
  return flat;
}

Tree unflatten(Flat flat) {
  final tree = <String, dynamic>{};
  flat.forEach((path, value) {
    final parts = path.split('/');
    var level = tree;
    for (final part in parts.take(parts.length - 1)) {
      level = (level[part] ??= <String, dynamic>{}) as Tree;
    }
    level[parts.last] = value;
  });
  return tree;
}

/// Every path above [path].
Iterable<String> _parents(String path) sync* {
  var at = path.lastIndexOf('/');
  while (at > 0) {
    yield path.substring(0, at);
    at = path.lastIndexOf('/', at - 1);
  }
}

/// What turns [from] into [to]: new values, and null for what is gone.
///
/// A value can turn into a branch or the other way round, as when one reaction
/// per person became several. The database refuses a change that names both a
/// path and something under it, and the new value replaces the old anyway, so
/// the removal is left out.
Map<String, Object?> changesBetween(Flat from, Flat to) {
  final changes = <String, Object?>{};
  to.forEach((path, value) {
    if (from[path] != value) changes[path] = value;
  });
  for (final path in from.keys) {
    if (!to.containsKey(path)) changes[path] = null;
  }
  final written = {
    for (final entry in changes.entries)
      if (entry.value != null) entry.key,
  };
  final above = {for (final path in written) ..._parents(path)};
  changes.removeWhere((path, value) =>
      value == null &&
      (above.contains(path) || _parents(path).any(written.contains)));
  return changes;
}

Flat applyChanges(Flat base, Map<String, Object?> changes) {
  final written = {
    for (final entry in changes.entries)
      if (entry.value != null) entry.key,
  };
  final above = {for (final path in written) ..._parents(path)};
  final result = Flat.of(base)
    ..removeWhere((path, _) =>
        above.contains(path) || _parents(path).any(written.contains));
  changes.forEach((path, value) {
    if (value == null) {
      result.remove(path);
    } else {
      result[path] = value;
    }
  });
  return result;
}

/// Applies one event of the database's live stream: `put` replaces whatever is
/// at [path], `patch` replaces each child it names.
Flat applyServerEvent(Flat flat, String event, String path, Object? data) {
  final result = Flat.of(flat);
  void put(String where, Object? value) {
    result.removeWhere((key, _) =>
        where.isEmpty || key == where || key.startsWith('$where/'));
    if (value is Map) {
      result.addAll(flatten(value.cast<String, dynamic>(), where));
    } else if (value != null && where.isNotEmpty) {
      result[where] = value;
    }
  }

  final at = path.replaceAll(RegExp(r'^/+|/+$'), '');
  if (event == 'put') {
    put(at, data);
  } else if (event == 'patch' && data is Map) {
    data.forEach((key, value) => put(at.isEmpty ? '$key' : '$at/$key', value));
  }
  return result;
}

bool sameFlat(Flat a, Flat b) => a.length == b.length && changesBetween(a, b).isEmpty;

/// What this phone last saw of a trip in the cloud. Whatever differs from the
/// trip on the phone is what still has to be sent, so changes made with no
/// connection simply wait here.
class TripMirror {
  TripMirror({Flat? server, Set<String>? uploaded})
      : server = server ?? {},
        uploaded = uploaded ?? {};

  factory TripMirror.fromJson(Tree json) => TripMirror(
        server: (json['server'] as Map<String, dynamic>).cast<String, Object>(),
        uploaded: (json['uploaded'] as List<dynamic>).cast<String>().toSet(),
      );

  Flat server;

  /// Pictures and sounds that are safely in the cloud.
  Set<String> uploaded;

  Map<String, Object?> pending(Flat local) => changesBetween(server, local);

  /// The cloud has accepted [sent].
  void confirm(Map<String, Object?> sent) {
    server = applyChanges(server, sent);
  }

  /// The cloud has changed. Returns what the phone should now hold: everything
  /// new from the cloud, plus this phone's changes that are still waiting.
  Flat receive(Flat local, String event, String path, Object? data) {
    final waiting = pending(local);
    server = applyServerEvent(server, event, path, data);
    return applyChanges(server, waiting);
  }

  Tree toJson() => {'server': server, 'uploaded': uploaded.toList()};
}
