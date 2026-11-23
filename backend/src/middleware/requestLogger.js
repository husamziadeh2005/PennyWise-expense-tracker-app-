import { randomUUID } from 'node:crypto';

/**
 * Gives every request an id (returned in the X-Request-Id header and in
 * error bodies) and logs one line when it finishes:
 *
 *   [a1b2c3d4] GET /api/transactions 200 34ms
 *
 * Tokens and request bodies are never logged.
 */
export function requestLogger({ silent = false } = {}) {
  return (req, res, next) => {
    req.id = randomUUID().slice(0, 8);
    res.setHeader('X-Request-Id', req.id);
    const started = process.hrtime.bigint();
    res.on('finish', () => {
      if (silent) return;
      const ms = Number(process.hrtime.bigint() - started) / 1e6;
      console.log(`[${req.id}] ${req.method} ${req.originalUrl.split('?')[0]} ${res.statusCode} ${ms.toFixed(0)}ms`);
    });
    next();
  };
}
