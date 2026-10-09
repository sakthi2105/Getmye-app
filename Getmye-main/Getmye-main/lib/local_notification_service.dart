// ignore: depend_on_referenced_packages
import 'package:firebase_core/firebase_core.dart';
// ignore: depend_on_referenced_packages
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_application_1/deliverystatus.dart';
// ignore: depend_on_referenced_packages
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

// Firebase Background Handler (Runs when app is in background)
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
  if (kDebugMode) {
    print("🔵 Background message received: ${message.notification?.title}");
  }
}

// Local Notifications setup
late FlutterLocalNotificationsPlugin localNotifications;

// Initialize Local Notifications
void _initializeLocalNotifications(BuildContext context) {
  localNotifications = FlutterLocalNotificationsPlugin();

  var androidInit = AndroidInitializationSettings('@mipmap/logo2');
  var iOSInit = DarwinInitializationSettings();
  var initSettings = InitializationSettings(android: androidInit, iOS: iOSInit);

  // Handling notification click actions
  localNotifications.initialize(initSettings, onDidReceiveNotificationResponse: (NotificationResponse notificationResponse) async {
    var payload = notificationResponse.payload;
    if (payload == "accept") {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (context) => DeliveryStatusPage()),
      );
    } else if (payload == "deny") {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (context) => DenyPage()),
      );
    }
  });
}

// Show notification with Accept & Decline buttons
Future<void> _showNotification(String title, String body, String itemName, String budget, String deliveryAddress) async {
  var androidDetails = AndroidNotificationDetails(
    'channel_id',
    'channel_name',
    importance: Importance.high,
    priority: Priority.high,
    actions: [
      AndroidNotificationAction("accept", "Accept"),
      AndroidNotificationAction("deny", "Decline"),
    ],
  );

  var notificationDetails = NotificationDetails(android: androidDetails);

  // Sending detailed data in the payload (itemName, budget, deliveryAddress)
  await localNotifications.show(
    0,
    title,
    body,
    notificationDetails,
    payload: "itemName:$itemName,budget:$budget,deliveryAddress:$deliveryAddress",
  );
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    _initializeLocalNotifications(context);

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Flutter Firebase Notification',
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      home: NotificationScreen(),
    );
  }
}

class NotificationScreen extends StatefulWidget {
  const NotificationScreen({super.key});

  @override
  // ignore: library_private_types_in_public_api
  _NotificationScreenState createState() => _NotificationScreenState();
}

class _NotificationScreenState extends State<NotificationScreen> {
  late FirebaseMessaging _messaging;
  String notificationMessage = "Waiting for notifications...";

  @override
  void initState() {
    super.initState();
    _initializeFirebaseMessaging();
  }

  void _initializeFirebaseMessaging() async {
    _messaging = FirebaseMessaging.instance;

    // Request permission
    NotificationSettings settings = await _messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );

    if (settings.authorizationStatus == AuthorizationStatus.authorized) {
      if (kDebugMode) {
        print("✅ User granted permission for notifications");
      }
    } else {
      if (kDebugMode) {
        print("❌ User declined notifications");
      }
    }

    // Get device token
    String? token = await _messaging.getToken();
    if (kDebugMode) {
      print("🔥 FCM Token: $token");
    }

    // Handle foreground notifications
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      if (kDebugMode) {
        print("🟢 Foreground message received: ${message.notification?.title}");
      }

      if (message.notification != null) {
        setState(() {
          notificationMessage = "${message.notification?.title} - ${message.notification?.body}";
        });

        // Show notification with item details
        _showNotification(
          message.notification!.title!,
          message.notification!.body!,
          "Sample Item", // Example item name, replace with your actual item name
          "500.00", // Example budget, replace with actual
          "123 Delivery Street", // Example address, replace with actual
        );
      }
    });

    // Handle background notification click
    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      if (kDebugMode) {
        print("🔴 Notification clicked: ${message.notification?.title}");
      }
      setState(() {
        notificationMessage = "Opened: ${message.notification?.title}";
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text("Firebase Notifications")),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              notificationMessage,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 18),
            ),
          ],
        ),
      ),
    );
  }
}

// Accept Page
class AcceptPage extends StatelessWidget {
  const AcceptPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text("Accept Page")),
      body: Center(
        child: Text(
          "You have accepted the order!",
          style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.green),
        ),
      ),
    );
  }
}

// Deny Page
class DenyPage extends StatelessWidget {
  const DenyPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text("Deny Page")),
      body: Center(
        child: Text(
          "You have denied the order!",
          style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.red),
        ),
      ),
    );
  }
}
