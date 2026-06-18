const express = require('express');
const jwt = require('jsonwebtoken');

const app = express();
app.use(express.json());

const PORT = process.env.PORT || 3001;
const SERVICE_NAME = 'auth-service';

const PRIVATE_KEY = process.env.JWT_PRIVATE_KEY;
const PUBLIC_KEY = process.env.JWT_PUBLIC_KEY;

if (!PRIVATE_KEY || !PUBLIC_KEY) {
  console.error('JWT_PRIVATE_KEY and JWT_PUBLIC_KEY must be set');
  process.exit(1);
}

// Fake user store — real version queries PostgreSQL
const USERS = {
  'jasvith@linkpulse.io': { id: 'user_001', name: 'Jasvith', password: 'password123' },
  'test@linkpulse.io':    { id: 'user_002', name: 'Test User', password: 'password123' },
};

let requestCount = 0;

// Health
app.get('/health', (req, res) => {
  res.json({ status: 'ok', service: SERVICE_NAME });
});

// Prometheus metrics stub
app.get('/metrics', (req, res) => {
  res.set('Content-Type', 'text/plain');
  res.send(`# HELP auth_requests_total Total requests\n# TYPE auth_requests_total counter\nauth_requests_total ${requestCount}\n`);
});

// POST /login — signs a JWT with the RSA private key
// RS256: private key signs, public key verifies
// Any service with the public key can verify without calling auth-service
app.post('/login', (req, res) => {
  const { email, password } = req.body;
  if (!email || !password) return res.status(400).json({ error: 'email and password required' });

  const user = USERS[email];
  if (!user || user.password !== password) return res.status(401).json({ error: 'invalid credentials' });

  const token = jwt.sign(
    { sub: user.id, email, name: user.name, role: 'user' },
    PRIVATE_KEY,
    { algorithm: 'RS256', expiresIn: '1h', issuer: 'linkpulse-auth', audience: 'linkpulse-api' }
  );

  console.log(`[${SERVICE_NAME}] issued token for ${email}`);
  requestCount++;
  res.json({ token, expires_in: 3600 });
});

// GET /validate — verifies JWT signature using PUBLIC key
// Called by shortener-service to validate the token before writing to Redis
app.get('/validate', (req, res) => {
  const authHeader = req.headers.authorization;
  if (!authHeader || !authHeader.startsWith('Bearer ')) {
    return res.status(401).json({ valid: false, error: 'missing Authorization header' });
  }

  const token = authHeader.split(' ')[1];
  try {
    const payload = jwt.verify(token, PUBLIC_KEY, {
      algorithms: ['RS256'],
      issuer: 'linkpulse-auth',
      audience: 'linkpulse-api',
    });
    requestCount++;
    res.json({ valid: true, user: { id: payload.sub, email: payload.email, name: payload.name, role: payload.role } });
  } catch (err) {
    res.status(401).json({ valid: false, error: err.message });
  }
});

// GET /.well-known/jwks.json — public key in JWKS format
// Kong API Gateway fetches this to validate JWTs at the edge
app.get('/.well-known/jwks.json', (req, res) => {
  res.json({
    keys: [{
      kty: 'RSA', use: 'sig', alg: 'RS256', kid: 'linkpulse-key-1',
      x5c: [PUBLIC_KEY.replace(/-----BEGIN PUBLIC KEY-----|-----END PUBLIC KEY-----|\n/g, '')],
    }]
  });
});

app.listen(PORT, () => {
  console.log(`[${SERVICE_NAME}] running on :${PORT}`);
});
