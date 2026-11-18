const mongoose = require('mongoose');

const WaitingCustomerSchema = new mongoose.Schema({
  user_id: {
    type: String,
    required: true,
    index: true
  },
  customer_name: {
    type: String,
    default: 'Customer'
  },
  customer_phone: {
    type: String,
    default: ''
  },
  reason: {
    type: String,
    default: 'no_partner_available'
  },
  requested_at: {
    type: Date,
    default: Date.now
  },
  notified: {
    type: Boolean,
    default: false
  }
}, {
  collection: 'waiting_customers',
  timestamps: { createdAt: 'created_at', updatedAt: 'updated_at' }
});

module.exports = mongoose.model('WaitingCustomer', WaitingCustomerSchema);

