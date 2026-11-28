const mongoose = require('mongoose');

const PreferredHotelSchema = new mongoose.Schema({
  hotel_id: {
    type: String,
    required: true,
    unique: true,
    index: true
  },
  name: {
    type: String,
    required: true,
    trim: true
  },
  area: {
    type: String,
    default: '',
    trim: true
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
  collection: 'preferred_hotels',
  timestamps: { createdAt: 'created_at', updatedAt: 'updated_at' }
});

module.exports = mongoose.model('PreferredHotel', PreferredHotelSchema);
