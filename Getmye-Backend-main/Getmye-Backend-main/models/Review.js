const mongoose = require('mongoose');

const ReviewSchema = new mongoose.Schema({
  review_id: {
    type: String,
    required: true,
    unique: true
  },
  order_id: {
    type: String,
    required: true,
    index: true
  },
  user_id: {
    type: String,
    required: true
  },
  partner_id: {
    type: String,
    required: true,
    index: true
  },
  rating: {
    type: Number,
    required: true,
    min: 1,
    max: 5
  },
  comment: {
    type: String,
    default: ''
  }
}, {
  collection: 'reviews',
  timestamps: { createdAt: 'created_at', updatedAt: 'updated_at' }
});

module.exports = mongoose.model('Review', ReviewSchema);
