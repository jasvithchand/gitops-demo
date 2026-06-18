const express = require('express');
const redis = require('redis');

const app = express();
const PORT = process.env.PORT || 3003;
const SERVICE_NAME = 'redirect-service';

// Pure Redis reads — this is the hot path
// Every click on every short link hits this service
// No auth required — redirects are public
const REDIS_URL = process.env.REDIS_URL || 'redis://redis-0.redis.data.svc.cluster.local:6379';

const redisClient = redis.createClient({
  url: REDIS_URL,
  socket: { reconnectStrategy: retries => Math.min(retries * 100, 3000) }
});

redisClient.on('error', err => console.error(`[${SERVICE_NAME}] Redis error:`, err.message));
redisClient.on('connect', () => console.log(`[${SERVICE_NAME}] connected to Redis`));

let redirectCount = 0;
let missCount = 0;

(async () => {
  await redisClient.connect();
  console.log(`[${SERVICE_NAME}] running on :${PORT}`);
})();

app.get('/health', (req, res) => {
  res.json({ status: 'ok', service: SERVICE_NAME, redis: redisClient.isReady });
});

// Prometheus metrics — these become the golden signals on Grafana
// redirects_total: request rate (use rate() in PromQL)
// misses_total: cache miss rate (should be near 0 for warm cache)
app.get('/metrics', (req, res) => {
  res.set('Content-Type', 'text/plain');
  res.send([
    '# HELP redirect_total Total redirects served',
    '# TYPE redirect_total counter',
    `redirect_total ${redirectCount}`,
    '# HELP redirect_miss_total Short codes not found in Redis',
    '# TYPE redirect_miss_total counter',
    `redirect_miss_total ${missCount}`,
  ].join('\n') + '\n');
});

// GET /:code — the hot path
// Reads the URL from Redis and issues a 302 redirect
// This is what k6 will hammer during load testing
// HPA will scale this service based on CPU when load spikes
app.get('/:code', async (req, res) => {
  const { code } = req.params;

  // Skip if it looks like a system path
  if (code === 'health' || code === 'metrics') return;

  try {
    const data = await redisClient.get(`link:${code}`);

    if (!data) {
      missCount++;
      return res.status(404).json({ error: 'link not found' });
    }

    const { url } = JSON.parse(data);
    redirectCount++;

    // Publish click event (stub — RabbitMQ consumer added in Phase 6)
    // In production: publish { code, url, userAgent, ip, timestamp } to queue
    // analytics-service consumes this asynchronously
    console.log(`[${SERVICE_NAME}] redirect ${code} -> ${url} (total: ${redirectCount})`);

    // 302 Found — temporary redirect
    // Browser follows this to the original URL
    res.redirect(302, url);
  } catch (err) {
    console.error(`[${SERVICE_NAME}] error:`, err.message);
    res.status(500).json({ error: 'internal error' });
  }
});
