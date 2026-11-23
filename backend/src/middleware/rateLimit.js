import { rateLimit } from 'express-rate-limit';

const handler = (req, res) =>
  res.status(429).json({
    error: { code: 'rate_limited', message: 'Too many requests. Please slow down and try again.', requestId: req.id },
  });

/** Per IP, before authentication: slows down anyone guessing tokens. */
export const ipLimiter = rateLimit({
  windowMs: 60_000,
  limit: 300,
  standardHeaders: 'draft-8',
  legacyHeaders: false,
  handler,
});

/** Per signed-in user (runs after requireAuth). */
export const userLimiter = rateLimit({
  windowMs: 60_000,
  limit: 120,
  standardHeaders: 'draft-8',
  legacyHeaders: false,
  keyGenerator: (req) => req.user.id,
  handler,
});

/** Uploads are expensive, so they get their own smaller budget. */
export const uploadLimiter = rateLimit({
  windowMs: 10 * 60_000,
  limit: 30,
  standardHeaders: 'draft-8',
  legacyHeaders: false,
  keyGenerator: (req) => req.user.id,
  handler,
});
