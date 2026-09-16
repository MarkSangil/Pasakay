import 'dart:async';
import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/utils/notification_event_type.dart';
import 'driver_repository.dart';

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
}

class PushNotificationService {
  PushNotificationService(this._repo);

  final DriverRepository _repo;
  void Function(String route)? onOpenRoute;
  void Function()? onInboxChanged;

  static final FlutterLocalNotificationsPlugin _local =
      FlutterLocalNotificationsPlugin();

  static const AndroidNotificationChannel _channel = AndroidNotificationChannel(
    'pasakay_driver_alerts',
    'Pasakay alerts',
    description: 'Schedule and system alerts for drivers',
    importance: Importance.max,
    playSound: true,
    enableVibration: true,
  );

  static bool _firebaseReady = false;
  static bool _localReady = false;
  static bool _backgroundHandlerBound = false;
  bool _listenersBound = false;
  String? _lastToken;
  String? _driverId;
  String? _startedForId;
  RealtimeChannel? _notifChannel;
  RealtimeChannel? _requestChannel;
  RealtimeChannel? _bookingChannel;
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
      // Hot restart can complain that the background handler is already set.
      // Still treat Firebase as usable so tokens + foreground display work.
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

  Future<void> startForDriver(String driverId) async {
    _startedForId = driverId;
    _driverId = driverId;
    _bindRealtimeInbox(driverId);

    if (kIsWeb || !_firebaseReady) {
      debugPrint(
        'Push start skipped (web=${kIsWeb}, firebaseReady=$_firebaseReady)',
      );
      return;
    }

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
    _bindRealtimeNotifications(driverId);

    final initial = await FirebaseMessaging.instance.getInitialMessage();
    if (initial != null) _handleOpen(initial);
  }

  Future<void> stop() async {
    final driverId = _driverId;
    final token = _lastToken;
    _driverId = null;
    _startedForId = null;
    await _notifChannel?.unsubscribe();
    await _requestChannel?.unsubscribe();
    await _bookingChannel?.unsubscribe();
    _notifChannel = null;
    _requestChannel = null;
    _bookingChannel = null;
    if (driverId != null && token != null) {
      try {
        await _repo.deleteDeviceToken(driverId: driverId, token: token);
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
      _notifyInboxChanged(message.data['event_type']?.toString());
    });
    FirebaseMessaging.onMessageOpenedApp.listen(_handleOpen);
  }

  void _bindRealtimeInbox(String driverId) {
    unawaited(_requestChannel?.unsubscribe());
    unawaited(_bookingChannel?.unsubscribe());
    _requestChannel = _repo.subscribeRideRequests(
      driverId: driverId,
      channelPrefix: 'driver-inbox-requests',
      onChange: (_) {
        debugPrint('Realtime ride_requests change → inbox refresh');
        onInboxChanged?.call();
      },
    );
    _bookingChannel = _repo.subscribeBookings(
      driverId: driverId,
      channelPrefix: 'driver-inbox-bookings',
      onChange: (_) {
        debugPrint('Realtime bookings change → inbox refresh');
        onInboxChanged?.call();
      },
    );
  }

  void _notifyInboxChanged(String? eventType) {
    switch (eventType) {
      case NotificationEventType.newRequest:
      case NotificationEventType.newDriverReview:
      case 'REQUEST_ACCEPTED':
      case 'REQUEST_REJECTED':
      case 'BOOKING_CONFIRMED':
      case 'BOOKING_COMPLETED':
      case 'BOOKING_CANCELLED':
      case 'BOOKING_FLAGGED':
        onInboxChanged?.call();
    }
  }

  void _bindRealtimeNotifications(String driverId) {
    unawaited(_notifChannel?.unsubscribe());
    _notifChannel = _repo.subscribeNotifications(
      driverId: driverId,
      onChange: (payload) {
        if (payload.eventType != PostgresChangeEvent.insert) return;
        final row = payload.newRecord;
        final title = (row['title'] as String?)?.trim();
        final body = (row['message_content'] as String?)?.trim() ?? '';
        if ((title == null || title.isEmpty) && body.isEmpty) return;
        debugPrint('Realtime notification insert → local heads-up');
        _notifyInboxChanged(row['event_type']?.toString());
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
    final driverId = _driverId;
    if (driverId == null) return;
    _lastToken = token;
    final platform = Platform.isIOS
        ? 'ios'
        : Platform.isAndroid
            ? 'android'
            : 'web';
    try {
      await _repo.registerDeviceToken(token: token, platform: platform);
      debugPrint('FCM token saved for driver $driverId');
    } catch (e) {
      debugPrint('Failed to save FCM token via RPC: $e — trying upsert');
      try {
        await _repo.upsertDeviceToken(
          driverId: driverId,
          token: token,
          platform: platform,
        );
        debugPrint('FCM token upserted for driver $driverId');
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
      isDriverApp: true,
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
        isDriverApp: true,
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
