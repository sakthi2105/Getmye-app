const express = require('express');
const router = express.Router();
const mongoose = require('mongoose');
const QuickCraving = require('../models/QuickCraving');
const Counter = require('../models/Counter');

// Helper to generate custom sequence ID e.g. CRV-001
async function getNextSequence(name, prefix = 'CRV-', pad = 3) {
  try {
    const counter = await Counter.findByIdAndUpdate(
      name,
      { $inc: { seq: 1 } },
      { new: true, upsert: true }
    );
    const seqStr = String(counter.seq).padStart(pad, '0');
    return `${prefix}${seqStr}`;
  } catch (err) {
    const random = Math.floor(100 + Math.random() * 900);
    return `${prefix}${Date.now().toString().slice(-4)}${random}`;
  }
}

// Helper to safely query either craving_id or _id without Mongoose CastError
function buildCravingFilter(id) {
  if (!id) return { _id: null };
  const cleanId = String(id).trim();
  if (mongoose.isValidObjectId(cleanId)) {
    return { $or: [{ craving_id: cleanId }, { _id: cleanId }] };
  }
  return { craving_id: cleanId };
}

// Default initial cravings with web & mobile image URLs
const DEFAULT_CRAVINGS = [
  {
    name: 'Chicken Biryani',
    budget: '49',
    rating: '4.5',
    time: '20-25 mins',
    cuisine: 'Biryani • North Indian',
    icon: '🍗',
    isVeg: false,
    image_url: 'https://images.unsplash.com/photo-1563379091339-03b21ab4a4f8?w=800&q=80',
    fallback_asset: 'assets/banner_biryani_crushing.jpg',
    order_index: 0
  },
  {
    name: 'Chicken Shawarma',
    budget: '30',
    rating: '4.6',
    time: '15-20 mins',
    cuisine: 'Rolls & Fast Food',
    icon: '🌯',
    isVeg: false,
    image_url: 'https://images.unsplash.com/photo-1529006557810-274b9b2fc783?w=800&q=80',
    fallback_asset: 'assets/banner_shawarma_crushing.jpg',
    order_index: 1
  },
  {
    name: 'Hot Momos',
    budget: '39',
    rating: '4.4',
    time: '15-20 mins',
    cuisine: 'Chinese • Street Food',
    icon: '🥟',
    isVeg: false,
    image_url: 'https://images.unsplash.com/photo-1625246333195-78d9c38ad449?w=800&q=80',
    fallback_asset: 'assets/banner_momos_crushing.jpg',
    order_index: 2
  },
  {
    name: 'Dosa with Sambar',
    budget: '60',
    rating: '4.7',
    time: '10-15 mins',
    cuisine: 'South Indian • Tiffin',
    icon: '🥞',
    isVeg: true,
    image_url: 'https://images.unsplash.com/photo-1668236543090-82eba5ee5976?w=800&q=80',
    fallback_asset: 'assets/craving_dosa.jpg',
    order_index: 3
  },
  {
    name: 'Paneer Butter Masala',
    budget: '120',
    rating: '4.5',
    time: '20-25 mins',
    cuisine: 'North Indian • Curry',
    icon: '🍛',
    isVeg: true,
    image_url: 'https://images.unsplash.com/photo-1631452180519-c014fe946bc7?w=800&q=80',
    fallback_asset: 'assets/craving_paneer.jpg',
    order_index: 4
  },
  {
    name: 'Chicken 65',
    budget: '110',
    rating: '4.6',
    time: '15-20 mins',
    cuisine: 'Starters • Appetizers',
    icon: '🍗',
    isVeg: false,
    image_url: 'https://images.unsplash.com/photo-1610057099431-d73a1c9d2f2f?w=800&q=80',
    fallback_asset: 'assets/craving_chicken65.jpg',
    order_index: 5
  },
  {
    name: 'Chicken Fried Rice',
    budget: '110',
    rating: '4.3',
    time: '20-25 mins',
    cuisine: 'Chinese • Fast Food',
    icon: '🍚',
    isVeg: false,
    image_url: 'https://images.unsplash.com/photo-1603133872878-684f208fb84b?w=800&q=80',
    fallback_asset: 'assets/banner_chicken_fried_rice.png',
    order_index: 6
  },
  {
    name: 'Fresh Mango Juice',
    budget: '50',
    rating: '4.8',
    time: '10-15 mins',
    cuisine: 'Beverages • Shakes',
    icon: '🥭',
    isVeg: true,
    image_url: 'https://images.unsplash.com/photo-1546173159-315724a31696?w=800&q=80',
    fallback_asset: 'assets/craving_mango_juice.jpg',
    order_index: 7
  }
];

// Helper to seed defaults if DB empty & backfill missing image_url
async function seedDefaultCravingsIfEmpty() {
  const count = await QuickCraving.countDocuments();
  if (count === 0) {
    console.log('Seeding initial Quick Cravings into database...');
    const toInsert = DEFAULT_CRAVINGS.map((c, idx) => ({
      ...c,
      craving_id: `DEFAULT-CRV-${idx + 1}`,
      is_active: true
    }));
    await QuickCraving.insertMany(toInsert);
  } else {
    // Backfill existing seeded items that lack image_url so Admin web doesn't 404
    for (const c of DEFAULT_CRAVINGS) {
      await QuickCraving.updateMany(
        {
          name: c.name,
          $or: [
            { image_url: null },
            { image_url: '' },
            { image_url: { $exists: false } }
          ],
          $and: [
            { image_base64: { $in: [null, ''] } }
          ]
        },
        { $set: { image_url: c.image_url } }
      );
    }
  }
}

// GET /api/quick-cravings/active - Customer App reads active cravings
router.get('/active', async (req, res) => {
  try {
    await seedDefaultCravingsIfEmpty();
    const cravings = await QuickCraving.find({ is_active: true })
      .sort({ order_index: 1, updated_at: -1 })
      .lean();

    res.json({
      success: true,
      count: cravings.length,
      cravings
    });
  } catch (err) {
    console.error('Error fetching active quick cravings:', err);
    res.status(500).json({ error: 'Failed to fetch quick cravings' });
  }
});

// GET /api/quick-cravings/all - Admin Portal reads all cravings
router.get('/all', async (req, res) => {
  try {
    await seedDefaultCravingsIfEmpty();
    const cravings = await QuickCraving.find()
      .sort({ order_index: 1, updated_at: -1 })
      .lean();

    res.json({
      success: true,
      count: cravings.length,
      cravings
    });
  } catch (err) {
    console.error('Error fetching all quick cravings:', err);
    res.status(500).json({ error: 'Failed to fetch quick cravings' });
  }
});

// POST /api/quick-cravings/upload - Admin creates a new Quick Craving
router.post('/upload', async (req, res) => {
  try {
    const {
      name,
      rating,
      budget,
      time,
      cuisine,
      icon,
      isVeg,
      image_base64,
      image_url,
      fallback_asset,
      order_index,
      is_active
    } = req.body;

    if (!name || !name.trim()) {
      return res.status(400).json({ error: 'Dish name is required' });
    }

    const cravingId = await getNextSequence('quick_craving_id', 'CRV-', 3);

    const newCraving = new QuickCraving({
      craving_id: cravingId,
      name: name.trim(),
      rating: rating ? String(rating).trim() : '4.5',
      budget: budget ? String(budget).trim() : '49',
      time: time ? String(time).trim() : '20-25 mins',
      cuisine: cuisine ? String(cuisine).trim() : 'Special Food',
      icon: icon || (isVeg === true ? '🥗' : '🍗'),
      isVeg: isVeg === true || String(isVeg).toLowerCase() === 'true',
      image_base64: image_base64 || null,
      image_url: image_url || null,
      fallback_asset: fallback_asset || 'assets/banner_biryani_crushing.jpg',
      order_index: order_index != null ? Number(order_index) : 0,
      is_active: is_active !== false
    });

    await newCraving.save();
    res.status(201).json({
      success: true,
      message: 'Quick Craving created successfully!',
      craving: newCraving
    });
  } catch (err) {
    console.error('Error uploading quick craving:', err);
    res.status(500).json({ error: 'Failed to save quick craving', details: err.message });
  }
});

// PUT /api/quick-cravings/:id - Admin updates a Quick Craving
router.put('/:id', async (req, res) => {
  try {
    const { id } = req.params;
    const filter = buildCravingFilter(id);
    const updates = { ...req.body };
    delete updates._id;
    delete updates.craving_id;

    if (updates.isVeg !== undefined) {
      updates.isVeg = updates.isVeg === true || String(updates.isVeg).toLowerCase() === 'true';
    }

    const updated = await QuickCraving.findOneAndUpdate(
      filter,
      { $set: updates },
      { new: true }
    );

    if (!updated) {
      return res.status(404).json({ error: 'Quick Craving not found' });
    }

    res.json({
      success: true,
      message: 'Quick Craving updated successfully!',
      craving: updated
    });
  } catch (err) {
    console.error('Error updating quick craving:', err);
    res.status(500).json({ error: 'Failed to update quick craving' });
  }
});

// DELETE /api/quick-cravings/:id - Admin deletes a Quick Craving
router.delete('/:id', async (req, res) => {
  try {
    const { id } = req.params;
    const filter = buildCravingFilter(id);
    const deleted = await QuickCraving.findOneAndDelete(filter);

    if (!deleted) {
      return res.status(404).json({ error: 'Quick Craving not found' });
    }

    res.json({
      success: true,
      message: 'Quick Craving deleted successfully!',
      craving: deleted
    });
  } catch (err) {
    console.error('Error deleting quick craving:', err);
    res.status(500).json({ error: 'Failed to delete quick craving' });
  }
});

// POST /api/quick-cravings/toggle/:id - Admin toggles active/inactive
router.post('/toggle/:id', async (req, res) => {
  try {
    const { id } = req.params;
    const filter = buildCravingFilter(id);
    const craving = await QuickCraving.findOne(filter);

    if (!craving) {
      return res.status(404).json({ error: 'Quick Craving not found' });
    }

    craving.is_active = !craving.is_active;
    await craving.save();

    res.json({
      success: true,
      message: `Quick Craving is now ${craving.is_active ? 'Active' : 'Inactive'}`,
      is_active: craving.is_active,
      craving
    });
  } catch (err) {
    console.error('Error toggling quick craving:', err);
    res.status(500).json({ error: 'Failed to toggle quick craving' });
  }
});

module.exports = router;
