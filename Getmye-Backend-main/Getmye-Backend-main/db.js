const mongoose = require('mongoose');
require('dotenv').config();

const MONGODB_URI = process.env.MONGODB_URI || 'mongodb+srv://sivaprakash9941_db_user:KcbbWhAckjNeyjcC@cluster0.rpfdlvi.mongodb.net/getmye_org?retryWrites=true&w=majority&appName=Cluster0';

async function connectDB() {
  try {
    await mongoose.connect(MONGODB_URI);
    console.log(' MongoDB connected successfully to getmye_org');
  } catch (error) {
    console.error(' MongoDB connection error:', error.message);
    process.exit(1);
  }
}

// Connect immediately on import for compatibility with require('./db')
connectDB();

module.exports = { mongoose, connectDB };
