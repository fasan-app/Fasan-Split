// SPDX-License-Identifier: MPL-2.0
// Fasan Split – CollabService, part: Receipt photos for the group. Split out of service.dart (13.11., Umbau U3, behaviour unchanged): the fields
// and constants stay in the class, these are its methods as an extension in the same library. MPL-2.0
part of 'service.dart';

extension CollabServicePhotos on CollabService {


  /// Local files of shared photos, by hash (to send them again, e.g. to a member who joins later).
  Map<String, String> get _photoFiles => {for (final e in (jsonDecode(prefs?.getString(CollabService._kPhotoFiles) ?? '{}') as Map).entries) '${e.key}': '${e.value}'};

  void _rememberPhoto(String hash, String path) => prefs?.setString(CollabService._kPhotoFiles, jsonEncode({..._photoFiles, hash: path}));

  void _preparePhotos(Bill b) {
    for (final orig in const [false, true]) {
      final path = orig ? b.originalPath : b.imagePath;
      if ((orig ? b.origRef : b.photoRef) != null || path == null || !imageExists(path)) continue;
      final key = '${b.id}:$orig';
      if (!_photoPreparing.add(key)) continue;
      unawaited(() async {
        try {
          final bytes = await readImage(path);
          if (bytes == null) return;
          // scan: 1000 px is sharp enough for the line pictures and the receipt view; original: 1200 px (Blossom will carry the
          // full resolution); about 100–250 KB each, 4–9 pieces
          final small = CollabService._shrink(bytes, orig ? 1200 : 1000, orig ? 60 : 70);
          if (small == null) return;
          final ref = PhotoSync.refOf(small);
          final file = await saveImage('ph_${ref.hash}.jpg', small);
          if (file != null) _rememberPhoto(ref.hash, file);
          if (orig) {
            b.origRef = ref.toJson();
          } else {
            b.photoRef = ref.toJson();
          }
          store.upsert(b, record: false); // goes out with the bill; the pieces follow in _sendPhotos
        } catch (_) {
          // no shared photo for this bill; the others keep the digital receipt
        } finally {
          _photoPreparing.remove(key);
        }
      }());
    }
  }

  /// Sends the pieces of every shared photo that this group has not had from this phone yet.
  void _sendPhotos() {
    final sent = {...?prefs?.getStringList(CollabService._kPhotoSent)};
    final files = _photoFiles;
    for (final g in groups.values) {
      for (final b in store.bills) {
        if (b.group != g.localName || b.read != BillRead.ok) continue;
        for (final r in [b.photoRef, b.origRef]) {
          final ref = PhotoRef.fromJson(r);
          final file = ref == null ? null : files[ref.hash];
          // a hidden bill's photo goes out under the bill's own key (again, even if it was sent before it was hidden: the new
          // event replaces the old one); without the key nothing is sent
          if (b.hidden && !g.session.hasBillKey(b.id)) continue;
          final billKey = b.hidden ? g.session.keyFor(GroupSession.bill(b.id)) : null;
          final key = '${g.secret.tag}:${ref?.hash}${b.hidden ? ':h' : ''}';
          if (ref == null || file == null || sent.contains(key) || !_photoSending.add(key)) continue;
          unawaited(() async {
            try {
              final bytes = await readImage(file);
              if (bytes == null || PhotoSync.hashOf(bytes) != ref.hash) return;
              if (await PhotoSync.send(g.session.relay, g.session.me, g.secret, bytes, key: billKey)) {
                prefs?.setStringList(CollabService._kPhotoSent, [...{...?prefs?.getStringList(CollabService._kPhotoSent), key}]);
              }
            } catch (_) {
              // tried again with the next change or start
            } finally {
              _photoSending.remove(key);
            }
          }());
        }
      }
    }
  }

  /// A shared bill names photos this device does not have: fetch them (one after another, scan first).
  void _wantPhotos(CollabGroup g, Bill b) {
    if (b.photosRemoved) return;
    for (final orig in const [false, true]) {
      final ref = PhotoRef.fromJson(orig ? b.origRef : b.photoRef);
      if (ref == null || imageExists(orig ? b.originalPath : b.imagePath)) continue;
      final failed = _photoFailed[ref.hash];
      if (failed != null && DateTime.now().difference(failed) < const Duration(minutes: 1)) continue;
      final job = (g.secret.tag, b.id, orig);
      if (!_photoQueue.contains(job)) orig ? _photoQueue.add(job) : _photoQueue.insert(0, job);
    }
    unawaited(_runPhotoQueue());
  }

  /// Photo of [b] is on its way from the group (the receipt view shows „kommt …“ instead of nothing).
  bool photoComing(Bill b) => !b.photosRemoved && b.photoRef != null && !imageExists(b.imagePath) && b.group != null && groupByLocalName(b.group!) != null;

  Future<void> _runPhotoQueue() async {
    if (_photoRunning) return;
    _photoRunning = true;
    try {
      while (_photoQueue.isNotEmpty && !_disposed) {
        final (tag, billId, orig) = _photoQueue.removeAt(0);
        final g = groups[tag];
        final b = store.bills.where((x) => x.id == billId).firstOrNull;
        final ref = PhotoRef.fromJson(orig ? b?.origRef : b?.photoRef);
        if (g == null || b == null || ref == null || imageExists(orig ? b.originalPath : b.imagePath)) continue;
        final bytes = await PhotoSync.fetch(g.session.relay, g.secret, ref, isMember: (pub) => g.session.memberKeys.contains(pub), key: b.hidden ? g.session.keyFor(GroupSession.bill(b.id)) : null);
        if (bytes == null) {
          _photoFailed[ref.hash] = DateTime.now();
          // nobody asks again by itself: try again after the pause, a few times (a new member may learn the members late)
          final tries = _photoRetries[ref.hash] = (_photoRetries[ref.hash] ?? 0) + 1;
          if (tries <= 5 && !_disposed) {
            _photoRetryTimers.add(Timer(const Duration(minutes: 1, seconds: 5), () {
              final gg = groups[tag], bb = store.bills.where((x) => x.id == billId).firstOrNull;
              if (!_disposed && gg != null && bb != null) _wantPhotos(gg, bb);
            }));
          }
          continue;
        }
        final path = await saveImage('ph_${ref.hash}.jpg', bytes);
        if (path == null) continue;
        _rememberPhoto(ref.hash, path);
        if (orig) {
          b.originalPath = path;
        } else {
          b.imagePath = path;
          try {
            b.imageAspect = await fillSnippets(b, bytes) ?? b.imageAspect;
          } catch (_) {}
        }
        store.upsert(b, record: false);
        _notify();
      }
    } finally {
      _photoRunning = false;
    }
  }
}
