const express = require('express');
const cors = require('cors');
const bodyParser = require('body-parser');
require('dotenv').config();

const profileRoutes = require('./routes/profile');
const addressRouter = require('./routes/address');
const editProfileRoutes = require('./routes/editp');
const proRoutes = require('./routes/pro');
const deliveryPersonRoutes = require('./routes/deliveryPerson');
const pendingKYC = require('./routes/getPendingKYC');
const orderRoutes = require('./routes/order');
const billRoutes = require('./routes/bill');
const paymentRoutes = require('./routes/payment');
const trackingRoutes = require('./routes/tracking');
const supportRoutes = require('./routes/support');

const app = express();
const PORT = process.env.PORT || 5000;

app.use(cors());
app.use(bodyParser.json({ limit: '50mb' }));
app.use(bodyParser.urlencoded({ limit: '50mb', extended: true }));
app.use(express.json({ limit: '50mb' }));

// API Routes
app.use('/api/profile', profileRoutes);
app.use('/api/address', addressRouter);
app.use('/api/editp', editProfileRoutes);
app.use('/api/pro', proRoutes);
app.use('/api/deliveryperson', deliveryPersonRoutes);
app.use('/api/getPersonByMobile', pendingKYC);
app.use('/api/getPendingKYC', pendingKYC);
app.use('/api/order', orderRoutes);
app.use('/api/bill', billRoutes);
app.use('/api/payment', paymentRoutes);
app.use('/api/tracking', trackingRoutes);
app.use('/api/support', supportRoutes);

// Health check endpoint
app.get('/api/health', (req, res) => {
  res.json({ status: 'OK', database: 'MongoDB', timestamp: new Date() });
});

// 404 handler for unknown routes (always return JSON, never HTML)
app.use((req, res) => {
  res.status(404).json({ error: `Route not found: ${req.method} ${req.originalUrl}` });
});

// Global error handler (always return JSON, never HTML)
app.use((err, req, res, next) => {
  console.error('Unhandled server error:', err);
  res.status(err.status || 500).json({ error: err.message || 'Internal server error' });
});

// Initialize Database connection
require('./db');

app.listen(PORT, '0.0.0.0', () => {
  console.log(`🚀 Server running on port ${PORT}`);
});

module.exports = app;
