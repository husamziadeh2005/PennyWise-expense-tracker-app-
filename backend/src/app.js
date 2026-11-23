import express from 'express';
import helmet from 'helmet';
import cors from 'cors';
import { config, isProduction } from './config.js';
import { requestLogger } from './middleware/requestLogger.js';
import { requireAuth } from './middleware/auth.js';
import { ipLimiter, userLimiter } from './middleware/rateLimit.js';
import { errorHandler, notFound } from './middleware/errorHandler.js';
import authRoutes from './routes/auth.routes.js';
import profileRoutes from './routes/profile.routes.js';
import categoryRoutes from './routes/categories.routes.js';
import transactionRoutes from './routes/transactions.routes.js';
import budgetRoutes from './routes/budgets.routes.js';
import statsRoutes from './routes/stats.routes.js';
import accountRoutes from './routes/account.routes.js';

/**
 * CORS = which WEBSITES may call this API from a browser (Flutter web).
 * Phone apps are not browsers, so CORS never affects them.
 *
 *  - CORS_ORIGINS set in .env  -> only those origins (use this in production)
 *  - otherwise, in development -> any http://localhost:<port> or 127.0.0.1,
 *    because `flutter run -d chrome` picks a random port each time
 *  - otherwise (production)    -> no browser access
 */
const LOCALHOST = /^http:\/\/(localhost|127\.0\.0\.1)(:\d+)?$/;

function corsOrigin(origin, callback) {
  if (!origin) return callback(null, false); // not a browser request
  if (config.corsOrigins.length) return callback(null, config.corsOrigins.includes(origin));
  return callback(null, !isProduction && LOCALHOST.test(origin));
}

/**
 * Builds the Express application. Every request flows through this chain
 * from top to bottom:
 *
 *   requestLogger -> helmet -> cors -> JSON parser -> ipLimiter
 *     -> /api/health (public)
 *     -> requireAuth -> userLimiter -> route -> (errors) errorHandler
 *
 * It is separate from server.js so tests can use the app without
 * opening a real network port.
 */
export function createApp({ silent = false, authenticate = requireAuth } = {}) {
  const app = express();

  app.disable('x-powered-by');
  app.set('trust proxy', config.trustProxy);

  app.use(requestLogger({ silent }));
  app.use(helmet());
  app.use(cors({ origin: corsOrigin }));
  app.use(express.json({ limit: '100kb' }));
  app.use(ipLimiter);

  // Public: lets you (or a hosting platform) check the server is up.
  app.get('/api/health', (req, res) => res.json({ status: 'ok', time: new Date().toISOString() }));

  // Everything below needs a valid Supabase access token.
  const api = express.Router();
  api.use(authenticate, userLimiter); // tests can swap in a fake authenticate
  api.use('/auth', authRoutes);
  api.use('/profile', profileRoutes);
  api.use('/categories', categoryRoutes);
  api.use('/transactions', transactionRoutes);
  api.use('/budgets', budgetRoutes);
  api.use('/stats', statsRoutes);
  api.use('/account', accountRoutes);
  app.use('/api', api);

  app.use(notFound);
  app.use(errorHandler);
  return app;
}
