import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../config/api_config.dart';
import '../theme/admin_theme.dart';

class OfferBannerPage extends StatefulWidget {
  const OfferBannerPage({super.key});

  @override
  State<OfferBannerPage> createState() => _OfferBannerPageState();
}

class _OfferBannerPageState extends State<OfferBannerPage> {
  Map<String, dynamic>? activeBanner;
  List<dynamic> bannerHistory = [];
  bool isLoading = true;
  bool isUploading = false;

  // Form Controllers
  final _titleController = TextEditingController(text: 'Special Dum Biriyani Deal');
  final _badgeController = TextEditingController(text: "TODAY'S SPECIAL");
  final _offerPriceController = TextEditingController(text: '65');
  final _originalPriceController = TextEditingController(text: '120');
  final _stockRemainingController = TextEditingController(text: '75');
  final _totalStockController = TextEditingController(text: '100');
  final _imageUrlController = TextEditingController();
  final _imageBase64Controller = TextEditingController();

  String _selectedUploadTab = 'presets'; // 'presets', 'url', 'base64'
  String? _previewImage; // Can be URL or Base64 or preset asset

  // Curated Preset Food & Biryani Deals for quick 1-click select
  final List<Map<String, String>> curatedPresets = [
    {
      'title': 'Woodfired Chicken Dum Biriyani',
      'price': '65',
      'orig': '120',
      'badge': 'HOT DEAL',
      'imageUrl': 'https://images.unsplash.com/photo-1563379091339-03b21ab4a4f8?w=800&q=80',
    },
    {
      'title': 'Authentic Mutton Dum Biriyani',
      'price': '140',
      'orig': '220',
      'badge': 'CHEF SPECIAL',
      'imageUrl': 'https://images.unsplash.com/photo-1589302168068-964664d93dc0?w=800&q=80',
    },
    {
      'title': 'Special Biriyani with Chicken 65',
      'price': '85',
      'orig': '150',
      'badge': 'BESTSELLER',
      'imageUrl': 'https://images.unsplash.com/photo-1633945274405-b6c8069047b0?w=800&q=80',
    },
    {
      'title': 'Juicy Chicken Shawarma Feast',
      'price': '70',
      'orig': '110',
      'badge': 'CRUSHING DEAL',
      'imageUrl': 'https://images.unsplash.com/photo-1529006557810-274b9b2fc783?w=800&q=80',
    },
  ];

  @override
  void initState() {
    super.initState();
    fetchActiveBanner();
    fetchBannerHistory();
  }

  @override
  void dispose() {
    _titleController.dispose();
    _badgeController.dispose();
    _offerPriceController.dispose();
    _originalPriceController.dispose();
    _stockRemainingController.dispose();
    _totalStockController.dispose();
    _imageUrlController.dispose();
    _imageBase64Controller.dispose();
    super.dispose();
  }

  Future<void> fetchActiveBanner() async {
    setState(() => isLoading = true);
    try {
      final res = await http.get(AdminApiConfig.bannerActive);
      if (res.statusCode == 200) {
        final decoded = json.decode(res.body);
        if (mounted && decoded is Map<String, dynamic> && decoded['banner'] != null) {
          setState(() {
            activeBanner = decoded['banner'] as Map<String, dynamic>;
            isLoading = false;
          });
        }
      }
    } catch (_) {
      if (mounted) setState(() => isLoading = false);
    }
  }

  Future<void> fetchBannerHistory() async {
    try {
      final res = await http.get(AdminApiConfig.bannerAll);
      if (res.statusCode == 200) {
        final decoded = json.decode(res.body);
        if (mounted && decoded is Map<String, dynamic> && decoded['banners'] is List) {
          setState(() {
            bannerHistory = decoded['banners'] as List;
          });
        }
      }
    } catch (_) {}
  }

  Future<void> _publishOfferBanner() async {
    setState(() => isUploading = true);

    String? finalBase64;
    String? finalUrl;

    if (_selectedUploadTab == 'base64' && _imageBase64Controller.text.trim().isNotEmpty) {
      finalBase64 = _imageBase64Controller.text.trim();
    } else if (_selectedUploadTab == 'url' && _imageUrlController.text.trim().isNotEmpty) {
      finalUrl = _imageUrlController.text.trim();
    } else if (_selectedUploadTab == 'presets' && _previewImage != null) {
      finalUrl = _previewImage;
    }

    try {
      final res = await http.post(
        AdminApiConfig.bannerUpload,
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'title': _titleController.text.trim(),
          'badge': _badgeController.text.trim(),
          'offer_price': int.tryParse(_offerPriceController.text) ?? 65,
          'original_price': int.tryParse(_originalPriceController.text) ?? 120,
          'stock_remaining': int.tryParse(_stockRemainingController.text) ?? 75,
          'total_stock': int.tryParse(_totalStockController.text) ?? 100,
          'image_base64': finalBase64,
          'image_url': finalUrl,
          'is_active': true,
        }),
      );

      if (!mounted) return;
      setState(() => isUploading = false);

      if (res.statusCode == 200 || res.statusCode == 201) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Row(
              children: [
                Icon(Icons.check_circle_rounded, color: Colors.white, size: 20),
                SizedBox(width: 8),
                Text('Offer Banner published to Customer Home page!'),
              ],
            ),
            backgroundColor: AdminColors.success,
          ),
        );
        fetchActiveBanner();
        fetchBannerHistory();
      } else {
        String errDetail = 'HTTP ${res.statusCode}';
        try {
          final errBody = json.decode(res.body);
          if (errBody is Map && (errBody['error'] != null || errBody['message'] != null)) {
            errDetail = '${errBody['error'] ?? errBody['message']} (${res.statusCode})';
          }
        } catch (_) {}
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to publish: $errDetail. (Ensure backend has /api/banner deployed)'),
            backgroundColor: AdminColors.danger,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => isUploading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error uploading: $e'),
          backgroundColor: AdminColors.danger,
        ),
      );
    }
  }

  Future<void> _updateQuickStock(int delta) async {
    final current = int.tryParse(_stockRemainingController.text) ?? 75;
    final newCount = (current + delta).clamp(0, 500);
    _stockRemainingController.text = newCount.toString();

    try {
      await http.put(
        AdminApiConfig.bannerStock,
        headers: {'Content-Type': 'application/json'},
        body: json.encode({'stock_remaining': newCount}),
      );
      fetchActiveBanner();
    } catch (_) {}
  }

  Future<void> _setActiveBanner(String bannerId) async {
    try {
      await http.post(AdminApiConfig.bannerToggle(bannerId));
      fetchActiveBanner();
      fetchBannerHistory();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Active offer updated!'),
            backgroundColor: AdminColors.success,
          ),
        );
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AdminColors.background,
      appBar: AppBar(
        title: const Text('Customer Home Offer Image & Banner Control'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh_rounded),
            onPressed: () {
              fetchActiveBanner();
              fetchBannerHistory();
            },
          ),
          const SizedBox(width: 8),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(color: AdminColors.border, height: 1),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 960),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Top Explanatory Banner
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AdminColors.primaryLight,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AdminColors.primarySubtle),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(Icons.campaign_rounded, color: AdminColors.primaryDark, size: 24),
                      ),
                      const SizedBox(width: 14),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Customer App Live Offer Control',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w800,
                                color: AdminColors.primaryDark,
                              ),
                            ),
                            SizedBox(height: 2),
                            Text(
                              'Any image uploaded here will directly appear on the customer home page in 1:1 ratio with dynamic price and stock counter.',
                              style: TextStyle(
                                fontSize: 12,
                                color: AdminColors.textSecondary,
                                height: 1.35,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),

                // Layout: Two columns on wider screens, stacked on mobile
                LayoutBuilder(
                  builder: (context, constraints) {
                    final isWide = constraints.maxWidth > 700;
                    return Flex(
                      direction: isWide ? Axis.horizontal : Axis.vertical,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Left / Top: Live Preview Card
                        Expanded(
                          flex: isWide ? 4 : 0,
                          child: _buildLivePreviewSection(),
                        ),
                        if (isWide) const SizedBox(width: 20) else const SizedBox(height: 20),

                        // Right / Bottom: Upload Form
                        Expanded(
                          flex: isWide ? 6 : 0,
                          child: _buildUploadFormSection(),
                        ),
                      ],
                    );
                  },
                ),
                const SizedBox(height: 26),

                // Banner History List
                _buildBannerHistorySection(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLivePreviewSection() {
    final title = activeBanner?['title'] ?? _titleController.text;
    final badge = activeBanner?['badge'] ?? _badgeController.text;
    final offerPrice = activeBanner?['offer_price'] ?? _offerPriceController.text;
    final origPrice = activeBanner?['original_price'] ?? _originalPriceController.text;
    final remainingStock = activeBanner?['stock_remaining'] ?? _stockRemainingController.text;
    final totalStock = activeBanner?['total_stock'] ?? _totalStockController.text;

    final bannerBase64 = activeBanner?['image_base64'] as String?;
    final bannerUrl = activeBanner?['image_url'] as String?;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AdminColors.border),
        boxShadow: const [
          BoxShadow(
            color: Color(0x06000000),
            blurRadius: 12,
            offset: Offset(0, 4),
          ),
        ],
      ),
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Live Customer View',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: AdminColors.textPrimary,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AdminColors.primaryLight,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircleAvatar(radius: 3, backgroundColor: AdminColors.primary),
                    SizedBox(width: 5),
                    Text(
                      'LIVE ON APP',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        color: AdminColors.primaryDark,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // 1:1 Aspect Ratio Card Preview (Exact replica of Customer Home)
          AspectRatio(
            aspectRatio: 1.0,
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                color: const Color(0xFFF1F5F9),
                border: Border.all(color: AdminColors.border),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    _buildPreviewImage(bannerBase64, bannerUrl),
                    // Badge Overlay
                    Positioned(
                      top: 10,
                      left: 10,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: const Color(0xFFEA580C),
                          borderRadius: BorderRadius.circular(8),
                          boxShadow: const [
                            BoxShadow(color: Colors.black26, blurRadius: 4, offset: Offset(0, 2)),
                          ],
                        ),
                        child: Text(
                          badge.toString().toUpperCase(),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),

          // Stock Counter Box
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xFFFFFBEB),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFFFDE68A)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    const Text('🔥', style: TextStyle(fontSize: 13)),
                    const SizedBox(width: 6),
                    Text(
                      '$remainingStock out of $totalStock biryanis remaining',
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF92400E),
                      ),
                    ),
                  ],
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF59E0B),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Text(
                    'FAST SELLING',
                    style: TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.w800),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),

          // Offer Button Preview
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(
              color: const Color(0xFF10B981),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Center(
              child: Text(
                'Get This Offer • ₹$offerPrice (Orig: ₹$origPrice)',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                  fontSize: 13,
                ),
              ),
            ),
          ),
          const SizedBox(height: 14),

          // Quick Stock Stepper
          Row(
            children: [
              const Text(
                'Adjust Stock:',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AdminColors.textSecondary),
              ),
              const Spacer(),
              IconButton.outlined(
                icon: const Icon(Icons.remove, size: 16),
                onPressed: () => _updateQuickStock(-5),
                style: IconButton.styleFrom(visualDensity: VisualDensity.compact),
              ),
              const SizedBox(width: 8),
              Text(
                '$remainingStock',
                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
              ),
              const SizedBox(width: 8),
              IconButton.outlined(
                icon: const Icon(Icons.add, size: 16),
                onPressed: () => _updateQuickStock(5),
                style: IconButton.styleFrom(visualDensity: VisualDensity.compact),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPreviewImage(String? base64String, String? url) {
    if (_previewImage != null && _previewImage!.startsWith('http')) {
      return Image.network(_previewImage!, fit: BoxFit.cover, errorBuilder: (_, __, ___) => _defaultImage());
    }
    if (base64String != null && base64String.isNotEmpty) {
      try {
        final clean = base64String.contains(',') ? base64String.split(',')[1] : base64String;
        return Image.memory(base64Decode(clean), fit: BoxFit.cover, errorBuilder: (_, __, ___) => _defaultImage());
      } catch (_) {}
    }
    if (url != null && url.isNotEmpty && url.startsWith('http')) {
      return Image.network(url, fit: BoxFit.cover, errorBuilder: (_, __, ___) => _defaultImage());
    }
    return _defaultImage();
  }

  Widget _defaultImage() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: const [
          Icon(Icons.fastfood_rounded, size: 40, color: AdminColors.primaryDark),
          SizedBox(height: 6),
          Text(
            'GetMye Dum Biriyani',
            style: TextStyle(fontWeight: FontWeight.w700, color: AdminColors.textSecondary),
          ),
        ],
      ),
    );
  }

  Widget _buildUploadFormSection() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AdminColors.border),
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Upload / Replace Offer Banner',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              color: AdminColors.textPrimary,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Choose a preset deal image, paste a photo URL, or upload Base64 data.',
            style: TextStyle(fontSize: 12, color: AdminColors.textSecondary),
          ),
          const SizedBox(height: 14),

          // Upload Source Mode Selector
          Row(
            children: [
              _buildTabPill('presets', 'Curated Library', Icons.photo_library_outlined),
              const SizedBox(width: 8),
              _buildTabPill('url', 'Image URL', Icons.link_rounded),
              const SizedBox(width: 8),
              _buildTabPill('base64', 'Base64 Data', Icons.data_object_rounded),
            ],
          ),
          const SizedBox(height: 16),

          // Presets Grid
          if (_selectedUploadTab == 'presets') ...[
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                crossAxisSpacing: 10,
                mainAxisSpacing: 10,
                childAspectRatio: 1.4,
              ),
              itemCount: curatedPresets.length,
              itemBuilder: (context, index) {
                final preset = curatedPresets[index];
                final isSelected = _previewImage == preset['imageUrl'];
                return InkWell(
                  onTap: () {
                    setState(() {
                      _previewImage = preset['imageUrl'];
                      _titleController.text = preset['title']!;
                      _offerPriceController.text = preset['price']!;
                      _originalPriceController.text = preset['orig']!;
                      _badgeController.text = preset['badge']!;
                    });
                  },
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: isSelected ? AdminColors.primary : AdminColors.border,
                        width: isSelected ? 2 : 1,
                      ),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(11),
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          Image.network(
                            preset['imageUrl']!,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => Container(color: AdminColors.background),
                          ),
                          Container(
                            decoration: const BoxDecoration(
                              gradient: LinearGradient(
                                colors: [Colors.transparent, Colors.black87],
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                              ),
                            ),
                          ),
                          Positioned(
                            bottom: 6,
                            left: 8,
                            right: 8,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  preset['title']!,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 10,
                                    fontWeight: FontWeight.w700,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                Text(
                                  '₹${preset['price']} (Orig: ₹${preset['orig']})',
                                  style: const TextStyle(
                                    color: Color(0xFF86EFAC),
                                    fontSize: 10,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (isSelected)
                            const Positioned(
                              top: 6,
                              right: 6,
                              child: CircleAvatar(
                                radius: 10,
                                backgroundColor: AdminColors.primary,
                                child: Icon(Icons.check, size: 12, color: Colors.white),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ],

          // URL Input Field
          if (_selectedUploadTab == 'url') ...[
            TextField(
              controller: _imageUrlController,
              onChanged: (val) => setState(() => _previewImage = val.trim()),
              decoration: const InputDecoration(
                hintText: 'https://example.com/banner-image.jpg',
                prefixIcon: Icon(Icons.image_outlined, size: 18),
                labelText: 'Image Web URL (HTTPS)',
              ),
            ),
          ],

          // Base64 Input Field
          if (_selectedUploadTab == 'base64') ...[
            TextField(
              controller: _imageBase64Controller,
              maxLines: 3,
              decoration: const InputDecoration(
                hintText: 'data:image/jpeg;base64,...',
                prefixIcon: Icon(Icons.code_rounded, size: 18),
                labelText: 'Paste Base64 Image String',
              ),
            ),
          ],
          const SizedBox(height: 18),

          // Offer Form Fields
          TextField(
            controller: _titleController,
            decoration: const InputDecoration(
              labelText: 'Offer Title / Food Name',
              hintText: 'e.g., Special Dum Biriyani Deal',
            ),
          ),
          const SizedBox(height: 12),

          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _badgeController,
                  decoration: const InputDecoration(
                    labelText: 'Tag / Badge',
                    hintText: 'e.g. HOT DEAL',
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  controller: _offerPriceController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Offer Price (₹)',
                    hintText: '65',
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  controller: _originalPriceController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Original (₹)',
                    hintText: '120',
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _stockRemainingController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Remaining Stock',
                    hintText: '75',
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  controller: _totalStockController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Total Daily Stock',
                    hintText: '100',
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),

          // Submit Button
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: isUploading ? null : _publishOfferBanner,
              icon: isUploading
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                    )
                  : const Icon(Icons.cloud_upload_rounded, size: 18),
              label: const Text('Save & Publish to Customer Home Page'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AdminColors.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTabPill(String tab, String label, IconData icon) {
    final isSelected = _selectedUploadTab == tab;
    return InkWell(
      onTap: () => setState(() => _selectedUploadTab = tab),
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? AdminColors.primary : AdminColors.background,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: isSelected ? AdminColors.primary : AdminColors.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: isSelected ? Colors.white : AdminColors.textSecondary),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: isSelected ? Colors.white : AdminColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBannerHistorySection() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AdminColors.border),
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Offer Banner Upload History (${bannerHistory.length})',
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: AdminColors.textPrimary,
                ),
              ),
              IconButton(
                icon: const Icon(Icons.refresh_rounded, size: 18),
                onPressed: fetchBannerHistory,
              ),
            ],
          ),
          const SizedBox(height: 12),

          if (bannerHistory.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 20),
              child: Center(
                child: Text(
                  'No previous banner uploads recorded yet.',
                  style: TextStyle(color: AdminColors.textMuted, fontSize: 13),
                ),
              ),
            )
          else
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: bannerHistory.length,
              separatorBuilder: (_, __) => const Divider(height: 1, color: AdminColors.borderLight),
              itemBuilder: (context, index) {
                final item = bannerHistory[index];
                final isActive = item['is_active'] == true;
                final bannerId = item['banner_id']?.toString() ?? '';
                final title = item['title'] ?? 'Offer Deal';
                final price = item['offer_price'] ?? 65;

                return ListTile(
                  contentPadding: const EdgeInsets.symmetric(vertical: 6),
                  leading: Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: AdminColors.primaryLight,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.local_offer_rounded, color: AdminColors.primaryDark, size: 20),
                  ),
                  title: Text(
                    title,
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                  ),
                  subtitle: Text(
                    'ID: $bannerId  •  Price: ₹$price  •  Stock: ${item['stock_remaining'] ?? 75}',
                    style: const TextStyle(fontSize: 11, color: AdminColors.textSecondary),
                  ),
                  trailing: isActive
                      ? Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: AdminColors.primaryLight,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: const Text(
                            'Active Live',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                              color: AdminColors.primaryDark,
                            ),
                          ),
                        )
                      : OutlinedButton(
                          onPressed: () => _setActiveBanner(bannerId),
                          style: OutlinedButton.styleFrom(
                            visualDensity: VisualDensity.compact,
                            padding: const EdgeInsets.symmetric(horizontal: 10),
                          ),
                          child: const Text('Make Active', style: TextStyle(fontSize: 11)),
                        ),
                );
              },
            ),
        ],
      ),
    );
  }
}

