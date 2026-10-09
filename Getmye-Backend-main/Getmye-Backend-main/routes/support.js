const express = require('express');
const router = express.Router();
const BugReport = require('../models/BugReport');
const Complaint = require('../models/Complaint');
const Feedback = require('../models/Feedback');
const { getNextSequence } = require('../models/Counter');

// POST /api/support/bug-report
router.post('/bug-report', async (req, res) => {
  try {
    const { user_id, user_name, user_phone, title, description, device_info } = req.body;
    if (!description) {
      return res.status(400).json({ error: 'Bug description is required' });
    }

    const reportId = await getNextSequence('bug_id', 'BUG-', 4);

    const report = new BugReport({
      report_id: reportId,
      user_id: user_id || 'guest',
      user_name: user_name || 'User',
      user_phone: user_phone || '',
      title: title || 'Application Bug Report',
      description,
      device_info: device_info || 'Android Mobile App'
    });

    await report.save();
    res.status(201).json({
      success: true,
      message: 'Bug report submitted successfully! Reference ID: ' + reportId,
      report
    });
  } catch (err) {
    console.error('Error submitting bug report:', err);
    res.status(500).json({ error: 'Failed to submit bug report', details: err.message });
  }
});

// GET /api/support/bug-reports
router.get('/bug-reports', async (req, res) => {
  try {
    const reports = await BugReport.find().sort({ created_at: -1 }).limit(50);
    res.json({ success: true, count: reports.length, reports });
  } catch (err) {
    res.status(500).json({ error: 'Failed to fetch bug reports' });
  }
});

// POST /api/support/complaint
router.post('/complaint', async (req, res) => {
  try {
    const { user_id, user_name, user_phone, order_id, subject, complaint_text } = req.body;
    if (!complaint_text) {
      return res.status(400).json({ error: 'Complaint text is required' });
    }

    const complaintId = await getNextSequence('complaint_id', 'CMP-', 4);

    const complaint = new Complaint({
      complaint_id: complaintId,
      user_id: user_id || 'guest',
      user_name: user_name || 'Customer',
      user_phone: user_phone || '',
      order_id: order_id || null,
      subject: subject || 'General Grievance',
      complaint_text
    });

    await complaint.save();
    res.status(201).json({
      success: true,
      message: 'Complaint registered successfully! Reference ID: ' + complaintId,
      complaint
    });
  } catch (err) {
    console.error('Error registering complaint:', err);
    res.status(500).json({ error: 'Failed to register complaint', details: err.message });
  }
});

// GET /api/support/complaints
router.get('/complaints', async (req, res) => {
  try {
    const complaints = await Complaint.find().sort({ created_at: -1 }).limit(50);
    res.json({ success: true, count: complaints.length, complaints });
  } catch (err) {
    res.status(500).json({ error: 'Failed to fetch complaints' });
  }
});

// POST /api/support/feedback
router.post('/feedback', async (req, res) => {
  try {
    const { user_id, user_name, user_phone, rating, category, feedback_text } = req.body;
    if (!rating || !feedback_text) {
      return res.status(400).json({ error: 'Rating and feedback message are required' });
    }

    const feedbackId = await getNextSequence('feedback_id', 'FB-', 4);

    const feedback = new Feedback({
      feedback_id: feedbackId,
      user_id: user_id || 'guest',
      user_name: user_name || 'Customer',
      user_phone: user_phone || '',
      rating: Number(rating) || 5,
      category: category || 'App Experience',
      feedback_text
    });

    await feedback.save();
    res.status(201).json({
      success: true,
      message: 'Thank you for your valuable feedback! Reference ID: ' + feedbackId,
      feedback
    });
  } catch (err) {
    console.error('Error submitting feedback:', err);
    res.status(500).json({ error: 'Failed to submit feedback', details: err.message });
  }
});

// GET /api/support/feedbacks
router.get('/feedbacks', async (req, res) => {
  try {
    const feedbacks = await Feedback.find().sort({ created_at: -1 }).limit(50);
    res.json({ success: true, count: feedbacks.length, feedbacks });
  } catch (err) {
    res.status(500).json({ error: 'Failed to fetch feedbacks' });
  }
});

module.exports = router;
