import 'api.dart';

// The browser prototype uses local demo snapshots, never production event streams.
class SessionEvents {
  SessionEvents(
    CollieApi api,
    void Function() refresh,
    void Function(Object) onError,
  );
  void start() {}
  void stop() {}
}
