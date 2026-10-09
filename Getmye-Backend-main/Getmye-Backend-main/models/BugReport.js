const mongoose = require('mongoose');

const BugReportSchema = new mongoose.Schema({
  report_id: {
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
    default: 'User'
  },
  user_phone: {
    type: String,
    default: ''
  },
  title: {
    type: String,
    required: true
  },
  description: {
    type: String,
    required: true
  },
  device_info: {
    type: String,
    default: 'Android App'
  },
  status: {
    type: String,
    enum: ['open', 'in_progress', 'resolved', 'closed'],
    default: 'open'
  }
}, {
  collection: 'bug_reports',
  timestamps: { createdAt: 'created_at', updatedAt: 'updated_at' }
});

module.exports = mongoose.model('BugReport', BugReportSchema);
