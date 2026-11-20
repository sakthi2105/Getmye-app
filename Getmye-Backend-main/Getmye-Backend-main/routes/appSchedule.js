const express = require('express');
const router = express.Router();
const AppSchedule = require('../models/AppSchedule');

// Helper to get current Indian Standard Time (IST) components
function getISTTime() {
  const now = new Date();
  const options = {
    timeZone: 'Asia/Kolkata',
    hour12: false,
    hour: '2-digit',
    minute: '2-digit',
    second: '2-digit'
  };
  const parts = new Intl.DateTimeFormat([], options).formatToParts(now);
  let h = 0, m = 0, s = 0;
  for (const p of parts) {
    if (p.type === 'hour') h = parseInt(p.value, 10);
    if (p.type === 'minute') m = parseInt(p.value, 10);
    if (p.type === 'second') s = parseInt(p.value, 10);
  }
  if (h === 24) h = 0;
  return {
    hours: h,
    minutes: m,
    seconds: s,
    totalSeconds: h * 3600 + m * 60 + s,
    timeString: `${String(h).padStart(2, '0')}:${String(m).padStart(2, '0')}`
  };
}

function parseTimeToSeconds(timeStr) {
  if (!timeStr || typeof timeStr !== 'string') return 0;
  const parts = timeStr.trim().split(':');
  const h = parseInt(parts[0], 10) || 0;
  const m = parseInt(parts[1], 10) || 0;
  return h * 3600 + m * 60;
}

async function getOrCreateSchedule() {
  let schedule = await AppSchedule.findOne({ schedule_id: 'DEFAULT_SCHEDULE' });
  if (!schedule) {
    schedule = new AppSchedule({
      schedule_id: 'DEFAULT_SCHEDULE',
      is_schedule_enabled: true,
      start_time: '12:30',
      end_time: '12:45',
      manual_override: 'auto',
      offline_title: 'Orders Opening Soon',
      offline_message: "We are accepting today's orders strictly during our scheduled slot. Please check back when the timer reaches zero!"
    });
    await schedule.save();
  }
  return schedule;
}

// GET /api/app-schedule/status - Public check for Customer & Admin
router.get('/status', async (req, res) => {
  try {
    const schedule = await getOrCreateSchedule();
    const ist = getISTTime();

    const startSec = parseTimeToSeconds(schedule.start_time);
    const endSec = parseTimeToSeconds(schedule.end_time);
    const currSec = ist.totalSeconds;

    let isWithinWindow = false;
    let secondsUntilClose = 0;
    let secondsUntilOpen = 0;

    if (startSec <= endSec) {
      isWithinWindow = currSec >= startSec && currSec < endSec;
      if (isWithinWindow) {
        secondsUntilClose = endSec - currSec;
      } else {
        if (currSec < startSec) {
          secondsUntilOpen = startSec - currSec;
        } else {
          secondsUntilOpen = (86400 - currSec) + startSec;
        }
      }
    } else {
      // Overnight window e.g. 23:00 to 02:00
      isWithinWindow = currSec >= startSec || currSec < endSec;
      if (isWithinWindow) {
        secondsUntilClose = currSec >= startSec ? (86400 - currSec) + endSec : endSec - currSec;
      } else {
        secondsUntilOpen = startSec - currSec;
      }
    }

    let isOnline = isWithinWindow;
    if (schedule.manual_override === 'always_online') {
      isOnline = true;
    } else if (schedule.manual_override === 'always_offline') {
      isOnline = false;
    } else if (!schedule.is_schedule_enabled) {
      isOnline = true; // If schedule feature disabled, default open
    }

    res.json({
      success: true,
      is_online: isOnline,
      current_time_ist: ist.timeString,
      start_time: schedule.start_time,
      end_time: schedule.end_time,
      is_schedule_enabled: schedule.is_schedule_enabled,
      manual_override: schedule.manual_override,
      seconds_until_close: secondsUntilClose,
      seconds_until_open: secondsUntilOpen,
      offline_title: schedule.offline_title,
      offline_message: schedule.offline_message,
      updated_at: schedule.updated_at
    });
  } catch (err) {
    console.error('Error in /api/app-schedule/status:', err);
    // Non-breaking fallback: allow normal operation if DB check errors out
    res.json({
      success: true,
      is_online: true,
      fallback: true,
      error: err.message
    });
  }
});

// GET /api/app-schedule/config - For Admin UI
router.get('/config', async (req, res) => {
  try {
    const schedule = await getOrCreateSchedule();
    res.json({ success: true, schedule });
  } catch (err) {
    res.status(500).json({ error: 'Failed to fetch schedule config', details: err.message });
  }
});

// POST /api/app-schedule/update - Admin updates schedule
router.post('/update', async (req, res) => {
  try {
    const {
      start_time,
      end_time,
      is_schedule_enabled,
      manual_override,
      offline_title,
      offline_message
    } = req.body;

    const schedule = await getOrCreateSchedule();

    if (start_time !== undefined) schedule.start_time = start_time.trim();
    if (end_time !== undefined) schedule.end_time = end_time.trim();
    if (is_schedule_enabled !== undefined) schedule.is_schedule_enabled = Boolean(is_schedule_enabled);
    if (manual_override !== undefined) schedule.manual_override = manual_override;
    if (offline_title !== undefined) schedule.offline_title = offline_title.trim();
    if (offline_message !== undefined) schedule.offline_message = offline_message.trim();
    schedule.updated_at = new Date();

    await schedule.save();

    res.json({
      success: true,
      message: 'App schedule updated successfully!',
      schedule
    });
  } catch (err) {
    console.error('Error updating schedule:', err);
    res.status(500).json({ error: 'Failed to update schedule', details: err.message });
  }
});

module.exports = router;
