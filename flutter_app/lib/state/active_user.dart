import 'package:flutter/foundation.dart';

class ActiveUser extends ChangeNotifier {
  String _userId = 'chairUser1';
  bool _isMuted = false;
  DateTime? _sittingStartTime;
  bool _alertShown = false;

  String get userId => _userId;
  bool get isMuted => _isMuted;
  DateTime? get sittingStartTime => _sittingStartTime;
  bool get alertShown => _alertShown;

  void setUser(String userId) {
    if (userId == _userId) return;
    _userId = userId;
    _sittingStartTime = null;
    _alertShown = false;
    notifyListeners();
  }

  void setMute(bool value) {
    _isMuted = value;
    notifyListeners();
  }

  void updateSession(DateTime? startTime, bool alertStatus) {
    _sittingStartTime = startTime;
    _alertShown = alertStatus;
    notifyListeners();
  }
}