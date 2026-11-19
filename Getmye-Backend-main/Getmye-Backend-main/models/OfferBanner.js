const mongoose = require('mongoose');

const OfferBannerSchema = new mongoose.Schema({
  banner_id: {
    type: String,
    required: true,
    unique: true,
    index: true
  },
  title: {
    type: String,
    default: "Special Dum Biriyani Deal"
  },
  badge: {
    type: String,
    default: "TODAY'S SPECIAL"
  },
  original_price: {
    type: Number,
    default: 120
  },
  offer_price: {
    type: Number,
    default: 65
  },
  stock_remaining: {
    type: Number,
    default: 75
  },
  total_stock: {
    type: Number,
    default: 100
  },
  image_base64: {
    type: String,
    default: null
  },
  image_url: {
    type: String,
    default: null
  },
  is_active: {
    type: Boolean,
    default: true
  }
}, {
  collection: 'offer_banners',
  timestamps: { createdAt: 'created_at', updatedAt: 'updated_at' }
});

module.exports = mongoose.model('OfferBanner', OfferBannerSchema);

