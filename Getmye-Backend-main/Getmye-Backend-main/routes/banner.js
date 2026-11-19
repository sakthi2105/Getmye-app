const express = require('express');
const router = express.Router();
const OfferBanner = require('../models/OfferBanner');
const { getNextSequence } = require('../models/Counter');

// Default fallback offer if nothing has been uploaded yet
const DEFAULT_OFFER = {
  banner_id: 'DEFAULT-001',
  title: 'Special Dum Biriyani',
  badge: "TODAY'S SPECIAL",
  original_price: 120,
  offer_price: 65,
  stock_remaining: 75,
  total_stock: 100,
  image_base64: null,
  image_url: 'assets/banner_biryani_65_4x5.jpg',
  is_active: true
};

// GET /api/banner/active - Retrieve current active offer banner for Customer Home
router.get('/active', async (req, res) => {
  try {
    const banner = await OfferBanner.findOne({ is_active: true }).sort({ updated_at: -1 }).lean();
    if (banner) {
      return res.json({ success: true, banner });
    }
    return res.json({ success: true, banner: DEFAULT_OFFER });
  } catch (err) {
    console.error('Error fetching active banner:', err);
    res.status(500).json({ error: 'Failed to fetch active banner', banner: DEFAULT_OFFER });
  }
});

// GET /api/banner/all - Retrieve all uploaded banners for Admin history
router.get('/all', async (req, res) => {
  try {
    const banners = await OfferBanner.find().sort({ updated_at: -1 }).limit(30).lean();
    res.json({ success: true, count: banners.length, banners });
  } catch (err) {
    console.error('Error fetching all banners:', err);
    res.status(500).json({ error: 'Failed to fetch banners' });
  }
});

// POST /api/banner/upload - Admin uploads or updates offer banner
router.post('/upload', async (req, res) => {
  try {
    const {
      title,
      badge,
      original_price,
      offer_price,
      stock_remaining,
      total_stock,
      image_base64,
      image_url,
      is_active
    } = req.body;

    const bannerId = await getNextSequence('banner_id', 'BNR-', 4);

    // If setting active, deactivate existing active banners
    const activeState = is_active !== false;
    if (activeState) {
      await OfferBanner.updateMany({}, { $set: { is_active: false } });
    }

    const newBanner = new OfferBanner({
      banner_id: bannerId,
      title: title || 'Special Dum Biriyani Deal',
      badge: badge || "HOT OFFER",
      original_price: Number(original_price) || 120,
      offer_price: Number(offer_price) || 65,
      stock_remaining: Number(stock_remaining) != null ? Number(stock_remaining) : 75,
      total_stock: Number(total_stock) || 100,
      image_base64: image_base64 || null,
      image_url: image_url || null,
      is_active: activeState
    });

    await newBanner.save();
    res.status(201).json({
      success: true,
      message: 'Offer banner uploaded and published successfully!',
      banner: newBanner
    });
  } catch (err) {
    console.error('Error uploading offer banner:', err);
    res.status(500).json({ error: 'Failed to save offer banner', details: err.message });
  }
});

// PUT /api/banner/stock - Quick update remaining stock count from Admin
router.put('/stock', async (req, res) => {
  try {
    const { stock_remaining, banner_id } = req.body;
    if (stock_remaining == null) {
      return res.status(400).json({ error: 'stock_remaining is required' });
    }

    const filter = banner_id ? { banner_id } : { is_active: true };
    const banner = await OfferBanner.findOneAndUpdate(
      filter,
      { $set: { stock_remaining: Number(stock_remaining) } },
      { returnDocument: 'after' }
    );

    res.json({ success: true, message: 'Stock updated', banner });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// POST /api/banner/toggle/:id - Set a specific banner as active
router.post('/toggle/:id', async (req, res) => {
  try {
    const { id } = req.params;
    await OfferBanner.updateMany({}, { $set: { is_active: false } });
    const banner = await OfferBanner.findOneAndUpdate(
      { $or: [{ banner_id: id }, { _id: id }] },
      { $set: { is_active: true } },
      { returnDocument: 'after' }
    );
    res.json({ success: true, banner });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

module.exports = router;

