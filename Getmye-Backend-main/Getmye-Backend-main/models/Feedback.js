const mongoose = require('mongoose');

const FeedbackSchema = new mongoose.Schema({
  feedback_id: {
    type: String,
    required: true,
    unique: true,
    index: true
  },
  user_id: {
    type: String,
    default: 'guest'
  },
  user_name: {
    type: String,
    default: 'Customer'
  },
  user_phone: {
    type: String,
    default: ''
  },
  rating: {
    type: Number,
    required: true,
    min: 1,
    max: 5
  },
  category: {
    type: String,
    default: 'General'
  },
  feedback_text: {
    type: String,
    required: true
  }
}, {
  collection: 'feedbacks',
  timestamps: { createdAt: 'created_at', updatedAt: 'updated_at' }
});

module.exports = mongoose.model('Feedback', FeedbackSchema);
