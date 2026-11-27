const mongoose = require('mongoose');

const SlidingBannerSchema = new mongoose.Schema({
  banner_id: {
    type: String,
    required: true,
    unique: true,
    index: true
  },
  title: {
    type: String,
    required: true,
    default: "Special Delicious Deal"
  },
  item: {
    type: String,
    required: true,
    default: "Food Item"
  },
  tag: {
    type: String,
    default: "CRUSHING OFFER"
  },
  original_price: {
    type: Number,
    default: 120
  },
  offer_price: {
    type: Number,
    default: 65
  },
  budget: {
    type: Number,
    default: 65
  },
  image_base64: {
    type: String,
    default: null
  },
  image_url: {
    type: String,
    default: null
  },
  fallback_asset: {
    type: String,
    default: 'assets/banner_biryani_crushing.jpg'
  },
  order_index: {
    type: Number,
    default: 0
  },
  is_active: {
    type: Boolean,
    default: true
  }
}, {
  collection: 'sliding_banners',
  timestamps: { createdAt: 'created_at', updatedAt: 'updated_at' }
});

module.exports = mongoose.model('SlidingBanner', SlidingBannerSchema);
