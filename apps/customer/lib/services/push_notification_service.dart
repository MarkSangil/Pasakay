import 'dart:async';
import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/utils/notification_event_type.dart';
import 'customer_repository.dart';

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
}

class PushNotificationService {
  PushNotificationService(this._repo);

  final CustomerRepository _repo;
  void Function(String route)? onOpenRoute;

  static final FlutterLocalNotificationsPlugin _local =
      FlutterLocalNotificationsPlugin();

  static const AndroidNotificationChannel _channel = AndroidNotificationChannel(
    'pasakay_passenger_alerts',
    'Pasakay alerts',
    description: 'Alerts for Pasakay passengers',
    importance: Importance.max,
    playSound: true,
    enableVibration: true,
  );

  static bool _firebaseReady = false;
  static bool _localReady = false;
  static bool _backgroundHandlerBound = false;
  bool _listenersBound = false;
  String? _lastToken;
  String? _commuterId;
  String? _startedForId;
  RealtimeChannel? _notifChannel;
  int _localNotifSeq = 0;
  String? _lastHeadsUpKey;
  DateTime? _lastHeadsUpAt;

  static Future<void> initializeFirebase() async {
    if (_firebaseReady) return;
    if (kIsWeb) return;
    try {
      await Firebase.initializeApp();
      if (!_backgroundHandlerBound) {
        FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
        _backgroundHandlerBound = true;
      }
      await _ensureLocalNotifications();
      _firebaseReady = true;
      debugPrint('Firebase messaging ready');
    } catch (e) {
      debugPrint('Firebase init warning: $e');
      try {
        await _ensureLocalNotifications();
        _firebaseReady = Firebase.apps.isNotEmpty;
      } catch (inner) {
        debugPrint('Firebase init failed: $inner');
      }
    }
  }

  static Future<void> _ensureLocalNotifications() async {
    if (_localReady) return;
    const androidInit =
        AndroidInitializationSettings('@drawable/ic_stat_pasakay');
    const iosInit = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );
    await _local.initialize(
      const InitializationSettings(android: androidInit, iOS: iosInit),
    );
    final androidPlugin = _local.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    await androidPlugin?.createNotificationChannel(_channel);
    _localReady = true;
  }

  Future<bool> areNotificationsEnabled() async {
    if (kIsWeb || !_firebaseReady) return false;
    if (Platform.isAndroid) {
      final android = _local.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      return await android?.areNotificationsEnabled() ?? false;
    }
    final settings = await FirebaseMessaging.instance.getNotificationSettings();
    return settings.authorizationStatus == AuthorizationStatus.authorized ||
        settings.authorizationStatus == AuthorizationStatus.provisional;
  }

  Future<bool> requestPermission() async {
    if (kIsWeb || !_firebaseReady) return false;
    await _ensureLocalNotifications();

    var granted = false;
    try {
      if (Platform.isAndroid) {
        final android = _local.resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
        final result = await android?.requestNotificationsPermission();
        granted = result ?? await areNotificationsEnabled();
      }

      final settings = await FirebaseMessaging.instance.requestPermission(
        alert: true,
        badge: true,
        sound: true,
        provisional: false,
      );
      granted = granted ||
          settings.authorizationStatus == AuthorizationStatus.authorized ||
          settings.authorizationStatus == AuthorizationStatus.provisional;
    } catch (e) {
      debugPrint('Notification permission request failed: $e');
    }

    debugPrint('Notification permission granted=$granted');
    return granted;
  }

  Future<void> startForCommuter(String commuterId) async {
    if (kIsWeb || !_firebaseReady) {
      debugPrint(
        'Push start skipped (web=${kIsWeb}, firebaseReady=$_firebaseReady)',
      );
      return;
    }

    _startedForId = commuterId;
    _commuterId = commuterId;

    final granted = await requestPermission();
    await FirebaseMessaging.instance.setForegroundNotificationPresentationOptions(
      alert: true,
      badge: true,
      sound: true,
    );

    if (!granted) {
      debugPrint('Notifications not granted; token may still be saved.');
    }

    await _refreshAndPersistToken();
    _bindFcmListeners();
    _bindRealtimeNotifications(commuterId);

    final initial = await FirebaseMessaging.instance.getInitialMessage();
    if (initial != null) _handleOpen(initial);
  }

  Future<void> stop() async {
    final commuterId = _commuterId;
    final token = _lastToken;
    _commuterId = null;
    _startedForId = null;
    await _notifChannel?.unsubscribe();
    _notifChannel = null;
    if (commuterId != null && token != null) {
      try {
        await _repo.deleteDeviceToken(commuterId: commuterId, token: token);
      } catch (_) {}
    }
    _lastToken = null;
  }

  Future<void> _refreshAndPersistToken() async {
    try {
      final token = await FirebaseMessaging.instance.getToken();
      if (token != null) {
        await _persistToken(token);
      } else {
        debugPrint('FCM getToken() returned null');
      }
    } catch (e) {
      debugPrint('FCM token unavailable: $e');
    }
  }

  void _bindFcmListeners() {
    if (_listenersBound) return;
    _listenersBound = true;
    FirebaseMessaging.instance.onTokenRefresh.listen(_persistToken);
    FirebaseMessaging.onMessage.listen((message) {
      debugPrint(
        'FCM foreground message: ${message.messageId} '
        'title=${message.notification?.title}',
      );
      unawaited(_showHeadsUp(
        title: message.notification?.title ??
            message.data['title']?.toString() ??
            'Pasakay',
        body: message.notification?.body ??
            message.data['body']?.toString() ??
            message.data['message_content']?.toString() ??
            '',
        eventType: message.data['event_type']?.toString(),
        data: message.data,
      ));
    });
    FirebaseMessaging.onMessageOpenedApp.listen(_handleOpen);
  }

  void _bindRealtimeNotifications(String commuterId) {
    unawaited(_notifChannel?.unsubscribe());
    _notifChannel = _repo.subscribeNotifications(
      commuterId: commuterId,
      onChange: (payload) {
        if (payload.eventType != PostgresChangeEvent.insert) return;
        final row = payload.newRecord;
        final title = (row['title'] as String?)?.trim();
        final body = (row['message_content'] as String?)?.trim() ?? '';
        if ((title == null || title.isEmpty) && body.isEmpty) return;
        debugPrint('Realtime notification insert → local heads-up');
        unawaited(_showHeadsUp(
          title: (title == null || title.isEmpty) ? 'Pasakay' : title,
          body: body,
          eventType: row['event_type']?.toString(),
          data: Map<String, dynamic>.from(row['data'] as Map? ?? const {}),
        ));
      },
    );
  }

  Future<void> _persistToken(String token) async {
    final commuterId = _commuterId;
    if (commuterId == null) return;
    _lastToken = token;
    final platform = Platform.isIOS
        ? 'ios'
        : Platform.isAndroid
            ? 'android'
            : 'web';
    try {
      await _repo.registerDeviceToken(token: token, platform: platform);
      debugPrint('FCM token saved for commuter $commuterId');
    } catch (e) {
      debugPrint('Failed to save FCM token via RPC: $e — trying upsert');
      try {
        await _repo.upsertDeviceToken(
          commuterId: commuterId,
          token: token,
          platform: platform,
        );
        debugPrint('FCM token upserted for commuter $commuterId');
      } catch (e2) {
        debugPrint('Failed to save FCM token: $e2');
      }
    }
  }

  void _handleOpen(RemoteMessage message) {
    final data = message.data;
    final route = NotificationEventType.routeFor(
      eventType: data['event_type'],
      data: data,
    );
    onOpenRoute?.call(route);
  }

  Future<void> _showHeadsUp({
    required String title,
    required String body,
    String? eventType,
    Map<String, dynamic>? data,
  }) async {
    try {
      final key = '$title|$body';
      final now = DateTime.now();
      if (_lastHeadsUpKey == key &&
          _lastHeadsUpAt != null &&
          now.difference(_lastHeadsUpAt!) < const Duration(seconds: 4)) {
        debugPrint('Heads-up debounced: $title');
        return;
      }
      _lastHeadsUpKey = key;
      _lastHeadsUpAt = now;

      await _ensureLocalNotifications();
      await _local.initialize(
        const InitializationSettings(
          android: AndroidInitializationSettings('@drawable/ic_stat_pasakay'),
          iOS: DarwinInitializationSettings(
            requestAlertPermission: true,
            requestBadgePermission: true,
            requestSoundPermission: true,
          ),
        ),
        onDidReceiveNotificationResponse: (response) {
          final payload = response.payload;
          if (payload != null && payload.isNotEmpty) {
            onOpenRoute?.call(payload);
          }
        },
      );

      if (body.isEmpty && title == 'Pasakay') {
        debugPrint('Heads-up skipped: empty title/body');
        return;
      }

      final stringData = <String, dynamic>{
        if (data != null)
          for (final e in data.entries)
            if (e.value != null) e.key: e.value,
      };

      final route = NotificationEventType.routeFor(
        eventType: eventType,
        data: stringData,
      );

      _localNotifSeq = (_localNotifSeq + 1) % 100000;
      final id = DateTime.now().millisecondsSinceEpoch.remainder(1 << 30) +
          _localNotifSeq;

      await _local.show(
        id,
        title,
        body,
        NotificationDetails(
          android: AndroidNotificationDetails(
            _channel.id,
            _channel.name,
            channelDescription: _channel.description,
            importance: Importance.max,
            priority: Priority.max,
            icon: '@drawable/ic_stat_pasakay',
            channelShowBadge: true,
            playSound: true,
            visibility: NotificationVisibility.public,
          ),
          iOS: const DarwinNotificationDetails(
            presentAlert: true,
            presentBadge: true,
            presentSound: true,
          ),
        ),
        payload: route,
      );
      debugPrint('Local heads-up shown id=$id title=$title');
    } catch (e, st) {
      debugPrint('Local heads-up failed: $e\n$st');
    }
  }
}
