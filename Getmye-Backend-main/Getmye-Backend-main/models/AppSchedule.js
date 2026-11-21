const mongoose = require('mongoose');

const appScheduleSchema = new mongoose.Schema({
  schedule_id: {
    type: String,
    required: true,
    unique: true,
    default: 'DEFAULT_SCHEDULE'
  },
  is_schedule_enabled: {
    type: Boolean,
    default: true
  },
  start_time: {
    type: String,
    default: '12:30' // 24-hour format HH:mm
  },
  end_time: {
    type: String,
    default: '12:45' // 24-hour format HH:mm
  },
  manual_override: {
    type: String,
    enum: ['auto', 'always_online', 'always_offline'],
    default: 'auto'
  },
  offline_title: {
    type: String,
    default: 'Orders Opening Soon'
  },
  offline_message: {
    type: String,
    default: "We are accepting today's orders strictly during our scheduled slot. Please check back when the timer reaches zero!"
  },
  updated_at: {
    type: Date,
    default: Date.now
  }
});

module.exports = mongoose.model('AppSchedule', appScheduleSchema);
