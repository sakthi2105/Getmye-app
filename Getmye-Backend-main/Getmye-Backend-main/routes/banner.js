const express = require('express');
const router = express.Router();
const OfferBanner = require('../models/OfferBanner');
const SlidingBanner = require('../models/SlidingBanner');
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

// Default fallback sliding banners for regular homepage carousel
const DEFAULT_SLIDING_BANNERS = [
  {
    banner_id: 'DEFAULT-SLD-1',
    title: 'Chicken Biryani',
    item: 'Chicken Biryani',
    tag: 'CRUSHING OFFER',
    original_price: 150,
    offer_price: 49,
    budget: 49,
    image_url: null,
    image_base64: null,
    fallback_asset: 'assets/banner_biryani_crushing.jpg',
    order_index: 0,
    is_active: true
  },
  {
    banner_id: 'DEFAULT-SLD-2',
    title: 'Hot & Spicy Chicken Shawarma',
    item: 'Chicken Shawarma',
    tag: 'CRUSHING OFFER',
    original_price: 110,
    offer_price: 30,
    budget: 30,
    image_url: null,
    image_base64: null,
    fallback_asset: 'assets/banner_shawarma_crushing.jpg',
    order_index: 1,
    is_active: true
  },
  {
    banner_id: 'DEFAULT-SLD-3',
    title: 'Hot & Steamy Momos',
    item: 'Hot & Steamy Momos',
    tag: 'CRUSHING OFFER',
    original_price: 120,
    offer_price: 39,
    budget: 39,
    image_url: null,
    image_base64: null,
    fallback_asset: 'assets/banner_momos_crushing.jpg',
    order_index: 2,
    is_active: true
  }
];

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

// =========================================================================
// 🎠 SLIDING BANNERS (REGULAR USER CAROUSEL BANNERS)
// =========================================================================

// GET /api/banner/sliding/active - Retrieve all active sliding banners for Regular Customer Home
router.get('/sliding/active', async (req, res) => {
  try {
    const banners = await SlidingBanner.find({ is_active: true })
      .sort({ order_index: 1, updated_at: -1 })
      .lean();

    if (banners && banners.length > 0) {
      return res.json({ success: true, count: banners.length, banners });
    }
    return res.json({ success: true, count: DEFAULT_SLIDING_BANNERS.length, banners: DEFAULT_SLIDING_BANNERS });
  } catch (err) {
    console.error('Error fetching active sliding banners:', err);
    res.status(500).json({ error: 'Failed to fetch sliding banners', banners: DEFAULT_SLIDING_BANNERS });
  }
});

// GET /api/banner/sliding/all - Retrieve all sliding banners for Admin list
router.get('/sliding/all', async (req, res) => {
  try {
    const banners = await SlidingBanner.find()
      .sort({ order_index: 1, updated_at: -1 })
      .lean();
    res.json({ success: true, count: banners.length, banners });
  } catch (err) {
    console.error('Error fetching all sliding banners:', err);
    res.status(500).json({ error: 'Failed to fetch sliding banners' });
  }
});

// POST /api/banner/sliding/upload - Admin uploads a new sliding banner
router.post('/sliding/upload', async (req, res) => {
  try {
    const {
      title,
      item,
      tag,
      original_price,
      offer_price,
      budget,
      image_base64,
      image_url,
      fallback_asset,
      order_index,
      is_active
    } = req.body;

    const bannerId = await getNextSequence('sliding_banner_id', 'SLD-', 3);

    const priceOffer = Number(offer_price) || 49;
    const priceBudget = Number(budget) || priceOffer;
    const priceOrig = Number(original_price) || Math.round(priceOffer * 1.5);

    const newBanner = new SlidingBanner({
      banner_id: bannerId,
      title: title || item || 'Special Offer Deal',
      item: item || title || 'Chicken Biryani',
      tag: tag || 'CRUSHING OFFER',
      original_price: priceOrig,
      offer_price: priceOffer,
      budget: priceBudget,
      image_base64: image_base64 || null,
      image_url: image_url || null,
      fallback_asset: fallback_asset || 'assets/banner_biryani_crushing.jpg',
      order_index: order_index != null ? Number(order_index) : 0,
      is_active: is_active !== false
    });

    await newBanner.save();
    res.status(201).json({
      success: true,
      message: 'Sliding banner created successfully!',
      banner: newBanner
    });
  } catch (err) {
    console.error('Error uploading sliding banner:', err);
    res.status(500).json({ error: 'Failed to save sliding banner', details: err.message });
  }
});

// Helper to safely query either banner_id or _id without Mongoose CastError
function buildIdFilter(id) {
  if (!id) return { _id: null };
  const cleanId = String(id).trim();
  const mongoose = require('mongoose');
  if (mongoose.isValidObjectId(cleanId)) {
    return { $or: [{ banner_id: cleanId }, { _id: cleanId }] };
  }
  return { banner_id: cleanId };
}

// PUT /api/banner/sliding/:id - Admin updates an existing sliding banner
router.put('/sliding/:id', async (req, res) => {
  try {
    const { id } = req.params;
    const filter = buildIdFilter(id);
    const updates = { ...req.body };
    delete updates._id;
    delete updates.banner_id;

    if (updates.offer_price != null) updates.offer_price = Number(updates.offer_price);
    if (updates.original_price != null) updates.original_price = Number(updates.original_price);
    if (updates.budget != null) updates.budget = Number(updates.budget);
    if (updates.order_index != null) updates.order_index = Number(updates.order_index);

    const updated = await SlidingBanner.findOneAndUpdate(
      filter,
      { $set: updates },
      { returnDocument: 'after' }
    );

    if (!updated) {
      return res.status(404).json({ error: 'Sliding banner not found' });
    }

    res.json({ success: true, message: 'Sliding banner updated', banner: updated });
  } catch (err) {
    console.error('Error updating sliding banner:', err);
    res.status(500).json({ error: err.message });
  }
});

// DELETE /api/banner/sliding/:id - Admin deletes a sliding banner
router.delete('/sliding/:id', async (req, res) => {
  try {
    const { id } = req.params;
    const cleanId = String(id || '').trim();
    const filter = buildIdFilter(cleanId);
    let deleted = await SlidingBanner.findOneAndDelete(filter);

    // If banner was a default preset in memory, ensure it is suppressed
    if (!deleted && cleanId.startsWith('DEFAULT-')) {
      const defaultMatch = DEFAULT_SLIDING_BANNERS.find(d => d.banner_id === cleanId);
      if (defaultMatch) {
        deleted = new SlidingBanner({
          ...defaultMatch,
          is_active: false
        });
        await deleted.save();
      }
    }

    res.json({
      success: true,
      message: 'Sliding banner deleted successfully',
      banner: deleted || { banner_id: cleanId }
    });
  } catch (err) {
    console.error('Error deleting sliding banner:', err);
    res.status(500).json({ error: err.message });
  }
});

// POST /api/banner/sliding/toggle/:id - Toggle active status of a sliding banner
router.post('/sliding/toggle/:id', async (req, res) => {
  try {
    const { id } = req.params;
    const cleanId = String(id || '').trim();
    const filter = buildIdFilter(cleanId);
    let banner = await SlidingBanner.findOne(filter);

    // If it's a default banner not yet written to DB, initialize it with toggled state
    if (!banner && cleanId.startsWith('DEFAULT-')) {
      const defaultMatch = DEFAULT_SLIDING_BANNERS.find(d => d.banner_id === cleanId);
      if (defaultMatch) {
        banner = new SlidingBanner({
          ...defaultMatch,
          is_active: false
        });
        await banner.save();
        return res.json({
          success: true,
          message: `Banner is now inactive`,
          banner
        });
      }
    }

    if (!banner) {
      return res.status(404).json({ error: 'Sliding banner not found' });
    }

    banner.is_active = !banner.is_active;
    await banner.save();

    res.json({ success: true, message: `Banner is now ${banner.is_active ? 'active' : 'inactive'}`, banner });
  } catch (err) {
    console.error('Error toggling sliding banner:', err);
    res.status(500).json({ error: err.message });
  }
});

module.exports = router;


