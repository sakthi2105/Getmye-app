import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'pay.dart';
import 'theme/app_theme.dart';

void main() {
  runApp(const MaterialApp(
    debugShowCheckedModeBanner: false,
    home: OrderStatusPage(
      customerLat: 10.9601,
      customerLng: 79.3845,
      driverLat: 10.9620,
      driverLng: 79.3860,
    ),
  ));
}

class OrderStatusPage extends StatefulWidget {
  final double customerLat;
  final double customerLng;
  final double? driverLat;
  final double? driverLng;

  const OrderStatusPage({
    super.key,
    required this.customerLat,
    required this.customerLng,
    this.driverLat,
    this.driverLng,
  });

  @override
  OrderStatusPageState createState() => OrderStatusPageState();
}

class OrderStatusPageState extends State<OrderStatusPage> {
  GoogleMapController? _mapController;
  final Set<Marker> _markers = {};
  late LatLng _initialPosition;
  bool _isLocationServiceEnabled = false;
  final int _currentStep = 2; // 0: Confirmed, 1: Preparing, 2: Out for Delivery, 3: Delivered

  @override
  void initState() {
    super.initState();
    _initialPosition = LatLng(widget.customerLat, widget.customerLng);
    _initializeLocation();
    _addMarkers();
  }

  Future<void> _initializeLocation() async {
    try {
      _isLocationServiceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!_isLocationServiceEnabled) return;

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) return;
      }
      if (permission == LocationPermission.deniedForever) return;

      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );

      if (mounted) {
        setState(() {
          _initialPosition = LatLng(position.latitude, position.longitude);
        });
        _mapController?.animateCamera(CameraUpdate.newLatLng(_initialPosition));
      }
    } catch (_) {}
  }

  void _addMarkers() {
    _markers.add(
      Marker(
        markerId: const MarkerId('customer'),
        position: LatLng(widget.customerLat, widget.customerLng),
        infoWindow: const InfoWindow(title: 'Delivery Location'),
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
      ),
    );

    if (widget.driverLat != null && widget.driverLng != null) {
      _markers.add(
        Marker(
          markerId: const MarkerId('driver'),
          position: LatLng(widget.driverLat!, widget.driverLng!),
          infoWindow: const InfoWindow(title: 'Rider Location'),
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
        ),
      );
    }
  }

  void _onMapCreated(GoogleMapController controller) {
    _mapController = controller;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Stack(
        children: [
          // Google Map Background
          Positioned.fill(
            child: RepaintBoundary(
              child: GoogleMap(
                onMapCreated: _onMapCreated,
                initialCameraPosition: CameraPosition(
                  target: _initialPosition,
                  zoom: 14.5,
                ),
                markers: _markers,
                myLocationEnabled: _isLocationServiceEnabled,
                myLocationButtonEnabled: false,
                zoomControlsEnabled: false,
                mapType: MapType.normal,
              ),
            ),
          ),

          // Top Floating Bar with Back Button & Title
          Positioned(
            top: MediaQuery.of(context).padding.top + 10,
            left: 16,
            right: 16,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(color: Colors.black.withValues(alpha: 0.1), blurRadius: 8),
                    ],
                  ),
                  child: IconButton(
                    icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18, color: AppColors.textPrimary),
                    onPressed: () => Navigator.pop(context),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(color: Colors.black.withValues(alpha: 0.1), blurRadius: 8),
                    ],
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.radar_rounded, size: 16, color: AppColors.primary),
                      SizedBox(width: 8),
                      Text(
                        'Live Order Tracking',
                        style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: AppColors.textPrimary),
                      ),
                    ],
                  ),
                ),
                Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(color: Colors.black.withValues(alpha: 0.1), blurRadius: 8),
                    ],
                  ),
                  child: IconButton(
                    icon: const Icon(Icons.help_outline_rounded, size: 20, color: AppColors.textSecondary),
                    onPressed: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Support is available 24/7 in Help & Support.')),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),

          // Bottom Order Tracking Panel
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.12),
                    blurRadius: 20,
                    offset: const Offset(0, -4),
                  ),
                ],
              ),
              child: SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      maxHeight: MediaQuery.of(context).size.height * 0.60,
                    ),
                    child: SingleChildScrollView(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                  Center(
                    child: Container(
                      width: 44,
                      height: 5,
                      decoration: BoxDecoration(
                        color: AppColors.border,
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),

                  // Delivery Time Header
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Estimated Delivery',
                            style: TextStyle(fontSize: 12, color: AppColors.textSecondary, fontWeight: FontWeight.w600),
                          ),
                          const SizedBox(height: 2),
                          Row(
                            children: [
                              Text(
                                '20 - 25 mins',
                                style: AppTypography.screenHeading.copyWith(fontSize: 22, color: AppColors.primaryDark),
                              ),
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: AppColors.primaryLight,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: const Text(
                                  'ON TIME',
                                  style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: AppColors.primaryDark),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: AppColors.primarySubtle,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.delivery_dining_rounded, size: 28, color: AppColors.primaryDark),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  const Divider(),
                  const SizedBox(height: 12),

                  // Order Status Timeline:
                  // ✓ Order Confirmed
                  // ✓ Preparing Food
                  // ● Out for Delivery
                  // ○ Delivered
                  const Text('Order Status', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: AppColors.textSecondary)),
                  const SizedBox(height: 12),
                  _buildTimeline(),

                  const SizedBox(height: 16),
                  const Divider(),
                  const SizedBox(height: 12),

                  // Driver Details Row
                  Row(
                    children: [
                      const CircleAvatar(
                        radius: 22,
                        backgroundImage: ResizeImage(
                          NetworkImage('https://randomuser.me/api/portraits/men/32.jpg'),
                          width: 120,
                        ),
                        backgroundColor: Color(0xFFE2E8F0),
                      ),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Mario Rossi',
                              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15, color: AppColors.textPrimary),
                            ),
                            Row(
                              children: [
                                Icon(Icons.star_rounded, size: 14, color: Color(0xFFF59E0B)),
                                SizedBox(width: 2),
                                Text(
                                  '4.9 (180+ deliveries)',
                                  style: TextStyle(fontSize: 11, color: AppColors.textSecondary, fontWeight: FontWeight.w500),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      // Call Driver Button
                      IconButton(
                        onPressed: () {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: const Row(
                                children: [
                                  Icon(Icons.phone_rounded, color: Colors.white, size: 18),
                                  SizedBox(width: 8),
                                  Text('Calling delivery partner Mario (+91 94421 88920)...'),
                                ],
                              ),
                              backgroundColor: AppColors.primaryDark,
                              behavior: SnackBarBehavior.floating,
                            ),
                          );
                        },
                        icon: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: AppColors.primaryLight,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(Icons.phone_rounded, color: AppColors.primaryDark, size: 18),
                        ),
                      ),
                    ],
                  ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    floatingActionButton: FloatingActionButton.extended(
      onPressed: () {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const PaymentPage()),
        );
      },
      label: const Text('Pay Now'),
      icon: const Icon(Icons.payment_rounded),
      backgroundColor: AppColors.primary,
    ),
    floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
    );
  }

  Widget _buildTimeline() {
    final steps = [
      {'title': 'Order Confirmed', 'done': true},
      {'title': 'Preparing Food', 'done': true},
      {'title': 'Out for Delivery', 'done': true, 'active': true},
      {'title': 'Delivered', 'done': false},
    ];

    return Row(
      children: List.generate(steps.length * 2 - 1, (index) {
        if (index.isOdd) {
          // Connector line
          int stepBefore = index ~/ 2;
          bool isCompleted = stepBefore < _currentStep;
          return Expanded(
            child: Container(
              height: 2.5,
              color: isCompleted ? AppColors.primary : AppColors.border,
            ),
          );
        } else {
          // Timeline node
          int stepIndex = index ~/ 2;
          final step = steps[stepIndex];
          bool isDone = step['done'] as bool;
          bool isActive = step['active'] == true;

          return Column(
            children: [
              Container(
                width: 26,
                height: 26,
                decoration: BoxDecoration(
                  color: isDone ? AppColors.primary : Colors.white,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: isDone ? AppColors.primary : AppColors.border,
                    width: 2,
                  ),
                  boxShadow: isActive
                      ? [
                          BoxShadow(
                            color: AppColors.primary.withValues(alpha: 0.4),
                            blurRadius: 8,
                            spreadRadius: 2,
                          ),
                        ]
                      : null,
                ),
                child: Center(
                  child: isDone
                      ? const Icon(Icons.check_rounded, size: 15, color: Colors.white)
                      : Container(
                          width: 8,
                          height: 8,
                          decoration: const BoxDecoration(
                            color: AppColors.border,
                            shape: BoxShape.circle,
                          ),
                        ),
                ),
              ),
              const SizedBox(height: 6),
              SizedBox(
                width: 65,
                child: Text(
                  step['title'] as String,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: isDone ? FontWeight.w700 : FontWeight.w500,
                    color: isDone ? AppColors.textPrimary : AppColors.textSecondary,
                  ),
                ),
              ),
            ],
          );
        }
      }),
    );
  }
}