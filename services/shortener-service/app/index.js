const express = require('express');
const redis = require('redis');
const axios = require('axios');
const crypto = require('crypto');

const app = express();
app.use(express.json());

const PORT = process.env.PORT || 3002;
const SERVICE_NAME = 'shortener-service';

// These come from the Helm chart ConfigMap
// Redis DNS: redis-0.redis.data.svc.cluster.local (headless service — direct pod addressing)
const REDIS_URL = process.env.REDIS_URL || 'redis://redis-0.redis.data.svc.cluster.local:6379';

// auth-service DNS: auth-service.services.svc.cluster.local (ClusterIP service)
const AUTH_SERVICE_URL = process.env.AUTH_SERVICE_URL || 'http://auth-service.services.svc.cluster.local:3001';

// Redis client with retry logic
const redisClient = redis.createClient({
  url: REDIS_URL,
  socket: { reconnectStrategy: retries => Math.min(retries * 100, 3000) }
});

redisClient.on('error', err => console.error(`[${SERVICE_NAME}] Redis error:`, err.message));
redisClient.on('connect', () => console.log(`[${SERVICE_NAME}] connected to Redis`));

let requestCount = 0;

// Connect to Redis on startup
(async () => {
  await redisClient.connect();
  console.log(`[${SERVICE_NAME}] running on :${PORT}`);
})();

// Health
app.get('/health', (req, res) => {
  res.json({ status: 'ok', service: SERVICE_NAME, redis: redisClient.isReady });
});

// Metrics stub
app.get('/metrics', (req, res) => {
  res.set('Content-Type', 'text/plain');
  res.send(`# HELP shortener_requests_total Total requests\n# TYPE shortener_requests_total counter\nshortener_requests_total ${requestCount}\n`);
});

// POST /links — creates a short code
// Requires: Authorization: Bearer <jwt>
// Body: { url: "https://example.com" }
// Flow:
//   1. Validate JWT by calling auth-service GET /validate
//   2. Generate a 6-char short code
//   3. Write code:url mapping to Redis (TTL 30 days)
//   4. Return the short code
app.post('/links', async (req, res) => {
  const { url } = req.body;
  if (!url) return res.status(400).json({ error: 'url is required' });

  // Step 1: validate the JWT by calling auth-service
  // This is a service-to-service call via ClusterIP DNS
  // In production Kong would handle this at the gateway — services wouldn't need to call auth-service
  try {
    const authResponse = await axios.get(`${AUTH_SERVICE_URL}/validate`, {
      headers: { Authorization: req.headers.authorization || '' },
      timeout: 3000,
    });

    if (!authResponse.data.valid) {
      return res.status(401).json({ error: 'invalid token' });
    }

    const user = authResponse.data.user;

    // Step 2: generate a short code — 6 random chars (alphanumeric)
    const code = crypto.randomBytes(4).toString('base64url').slice(0, 6);

    // Step 3: store in Redis
    // Key:   link:<code>
    // Value: JSON with url, user, created timestamp
    // TTL:   30 days (2592000 seconds)
    await redisClient.setEx(
      `link:${code}`,
      2592000,
      JSON.stringify({ url, userId: user.id, createdAt: new Date().toISOString() })
    );

    console.log(`[${SERVICE_NAME}] created short code ${code} for user ${user.id} -> ${url}`);
    requestCount++;

    res.status(201).json({
      code,
      short_url: `http://redirect-service.services.svc.cluster.local:3003/${code}`,
      original_url: url,
    });

  } catch (err) {
    if (err.response?.status === 401) {
      return res.status(401).json({ error: 'unauthorized' });
    }
    console.error(`[${SERVICE_NAME}] error:`, err.message);
    res.status(500).json({ error: 'internal error' });
  }
});

// GET /links/:code — looks up a short code in Redis
app.get('/links/:code', async (req, res) => {
  const { code } = req.params;
  try {
    const data = await redisClient.get(`link:${code}`);
    if (!data) return res.status(404).json({ error: 'link not found' });

    requestCount++;
    res.json(JSON.parse(data));
  } catch (err) {
    res.status(500).json({ error: 'internal error' });
  }
});
