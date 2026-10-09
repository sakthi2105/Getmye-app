const mongoose = require('mongoose');

const PaymentSchema = new mongoose.Schema({
  payment_id: {
    type: String,
    required: true,
    unique: true,
    index: true
  },
  order_id: {
    type: String,
    required: true,
    index: true
  },
  bill_id: {
    type: String,
    default: null
  },
  user_id: {
    type: String,
    required: true,
    index: true
  },
  amount: {
    type: Number,
    required: true
  },
  payment_method: {
    type: String,
    enum: ['upi', 'gpay', 'phonepe', 'cod', 'card', 'wallet'],
    required: true
  },
  payment_status: {
    type: String,
    enum: ['pending', 'success', 'failed'],
    default: 'pending'
  },
  transaction_reference: {
    type: String,
    default: null
  },
  cod_otp: {
    type: String,
    default: null
  },
  is_cod_verified: {
    type: Boolean,
    default: false
  },
  paid_at: {
    type: Date,
    default: null
  }
}, {
  collection: 'payments',
  timestamps: { createdAt: 'created_at', updatedAt: 'updated_at' }
});

module.exports = mongoose.model('Payment', PaymentSchema);
