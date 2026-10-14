# GetMye - Delivery Partner App (Flutter)

A comprehensive Flutter application for delivery partners to receive and manage food delivery orders, track locations, chat with customers, and earn money.

## Features

- **Partner Registration & Onboarding**: Complete registration with OTP verification
- **Profile Management**: Upload profile picture, view earnings, edit details
- **Live Order Tracking**:
  - Real-time order notifications
  - GPS location tracking (Partner & Customer)
  - Map-based route visualization
  - Estimated time of arrival (ETA)
- **Order Management**:
  - Accept/reject orders
  - Start/stop delivery
  - Mark as delivered
  - Pickup/drop confirmation
- **Billing System**:
  - View order bill
  - Pay via Cashfree Gateway (UPI, Cards, Netbanking)
  - COD payment with OTP verification
  - Order summary with item cost, delivery charge, and tips
- **Communication**:
  - In-app chat with customers
  - Send/receive text messages
  - Voice messages (planned)
  - Send photos (planned)
- **Notifications**:
  - Push notifications for new orders
  - Sound effects (pickup/drop/delivery)
- **Earning Tracking**:
  - Daily/monthly earnings view
  - Transaction history
- **Authentication**:
  - Phone number verification with OTP
  - Secure login with backend

## Tech Stack

- **Frontend**: Flutter
- **Backend**: Node.js + Express.js
- **Database**: MongoDB
- **Payment Gateway**: Cashfree Gateway (UPI, Cards, Netbanking)
- **Maps**: Google Maps Flutter
- **Location Services**: Geolocator

## Project Structure

```
lib/
├── api_config.dart              # API base URL and configuration
├── pay.dart                     # Payment gateway integration (Cashfree)
├── payment_cashfree.dart        # Cashfree specific payment implementation
├── delivery_bill_flow.dart      # Delivery workflow & order management
├── order_chat_sheet.dart        # In-app chat UI
├── services/
│   ├── api_service.dart         # HTTP API client
│   ├── alarm_service.dart       # Sound effects
│   ├── app_notification_service.dart # Firebase notifications
│   ├── route_service.dart       # Google Maps route calculation
│   └── upi_payment_service.dart   # UPI payment handling
├── theme/
│   └── app_theme.dart           # Custom app theme
└── main.dart                    # Application entry point
```

## Configuration

### Environment Variables

Create a `.env` file in the `Getmye-main/lib` directory:

```env
# API Base URL
API_BASE_URL=http://[IP_ADDRESS]/api

# Firebase (add your Firebase config here)
FIREBASE_CONFIG=your_firebase_config

# Cashfree Payments (from backend .env)
CASHFREE_APP_ID=your_cashfree_app_id
CASHFREE_SECRET_KEY=your_cashfree_secret_key
```

### Firebase Setup

1. Get your Firebase project configuration from the Firebase Console
2. Update `lib/api_config.dart` with your project details
3. Run `dart run flutterfire configure` to configure FlutterFire

### Cashfree Payments Setup

1. Register on Cashfree Payments (sandbox for testing)
2. Get your `app_id` and `secret_key`
3. Add them to your backend's `.env` file
4. Update `lib/pay.dart` with your configuration

## Dependencies

### Core Dependencies

```yaml
dependency_overrides:
  google_maps_flutter:
    git:
      url: https://github.com/googlemaps/flutter-google-maps

dependencies:
  flutter:
    sdk: flutter
  cupertino_icons: ^1.0.2
  google_maps_flutter: ^2.7.0
  geolocator: ^11.0.0
  http: ^1.2.2
  shared_preferences: ^2.4.0
  url_launcher: ^6.3.2
  firebase_core: ^4.2.1
  firebase_messaging: ^14.10.1
  flutter_local_notifications: ^17.2.1
  path_provider: ^2.1.5
  flutter_sound: ^2.4.0
  fluttertoast: ^8.2.14
  flutter_sound_platform_interface: ^2.5.0
  audioplayers: ^6.2.1
  image_picker: ^1.1.2
  permission_handler: ^12.0.1
  flutter_rating_bar: ^4.0.1
  intl: ^0.19.0
  http_parser: ^4.1.8
  uuid: ^4.5.1
  flutter_dotenv: ^5.1.0
```

### Dev Dependencies

```yaml
dev_dependencies:
  flutter_test:
    sdk: flutter
  flutter_lints: ^5.0.0
```

## Usage

### Running the App

1. Install dependencies:
   ```bash
   flutter pub get
   ```
2. Start the Flutter app:
   ```bash
   flutter run
   ```

### API Endpoints

#### Authentication
- `POST /api/auth/send-otp` - Send OTP to phone number
- `POST /api/auth/verify-otp` - Verify OTP and login

#### Orders
- `GET /api/order/delivery/new` - Get new delivery orders
- `GET /api/order/delivery/active` - Get active delivery orders
- `GET /api/order/status/:orderId` - Check order status
- `POST /api/order/accept/:orderId` - Accept an order
- `POST /api/order/start-delivery/:orderId` - Start delivery
- `POST /api/order/mark-delivered/:orderId` - Mark as delivered

#### Chat
- `GET /api/chat/messages/:orderId` - Get chat messages
- `POST /api/chat/messages` - Send a message

#### Payments
- `GET /api/payment/cashfree/config` - Get Cashfree configuration
- `POST /api/payment/cashfree/create-link` - Create payment link
- `GET /api/payment/cashfree/status/:linkId` - Verify payment status

#### Profile & Earnings
- `GET /api/profile` - Get delivery partner profile
- `GET /api/earnings/daily` - Get daily earnings
- `GET /api/earnings/monthly` - Get monthly earnings

### Cashfree Payments

**Create Payment Link**
```bash
curl -X POST https://sandbox.cashfree.com/pg/links \
  -H "Content-Type: application/json" \
  -H "x-client-id: YOUR_APP_ID" \
  -H "x-client-secret: YOUR_SECRET_KEY" \
  -H "x-api-version: 2023-08-01" \
  -d '{
    "link_id": "order-123",
    "link_amount": 100.00,
    "link_currency": "INR",
    "link_purpose": "Order Payment",
    "customer_details": {
      "customer_phone": "9999999999",
      "customer_name": "Customer"
    },
    "link_meta": {
      "return_url": "https://example.com/payment-success"
    }
  }'
```

**Verify Payment Status**
```bash
curl -X GET https://sandbox.cashfree.com/pg/links/order-123 \
  -H "x-client-id: YOUR_APP_ID" \
  -H "x-client-secret: YOUR_SECRET_KEY" \
  -H "x-api-version: 2023-08-01"
```

## Development

### Coding Standards