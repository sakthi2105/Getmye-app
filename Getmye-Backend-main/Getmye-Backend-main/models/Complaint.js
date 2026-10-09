const mongoose = require('mongoose');

const ComplaintSchema = new mongoose.Schema({
  complaint_id: {
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
  order_id: {
    type: String,
    default: null
  },
  subject: {
    type: String,
    required: true
  },
  complaint_text: {
    type: String,
    required: true
  },
  status: {
    type: String,
    enum: ['pending', 'investigating', 'resolved', 'closed'],
    default: 'pending'
  }
}, {
  collection: 'complaints',
  timestamps: { createdAt: 'created_at', updatedAt: 'updated_at' }
});

module.exports = mongoose.model('Complaint', ComplaintSchema);
