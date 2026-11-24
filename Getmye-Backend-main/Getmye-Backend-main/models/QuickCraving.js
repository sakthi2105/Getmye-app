const mongoose = require('mongoose');

const QuickCravingSchema = new mongoose.Schema({
  craving_id: {
    type: String,
    required: true,
    unique: true,
    index: true
  },
  name: {
    type: String,
    required: true,
    trim: true,
    default: "Chicken Biryani"
  },
  rating: {
    type: String,
    default: "4.5"
  },
  budget: {
    type: String,
    default: "49"
  },
  time: {
    type: String,
    default: "20-25 mins"
  },
  cuisine: {
    type: String,
    default: "Biryani • North Indian"
  },
  icon: {
    type: String,
    default: "🍗"
  },
  isVeg: {
    type: Boolean,
    default: false
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
  collection: 'quick_cravings',
  timestamps: { createdAt: 'created_at', updatedAt: 'updated_at' }
});

module.exports = mongoose.model('QuickCraving', QuickCravingSchema);
