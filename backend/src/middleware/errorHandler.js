import { ApiError, fromSupabaseError } from '../lib/errors.js';
import { isProduction } from '../config.js';

/** 404 for any route that does not exist. */
export function notFound(req, res, next) {
  next(new ApiError(404, 'route_not_found', `Route ${req.method} ${req.path} does not exist.`));
}

/**
 * Last middleware in the chain: every thrown error ends up here.
 * Express 5 forwards errors from async route handlers automatically,
 * so routes can simply `throw`.
 */
// eslint-disable-next-line no-unused-vars
export function errorHandler(err, req, res, next) {
  let error = err instanceof ApiError ? err : null;

  // Malformed JSON body sent by the client
  if (!error && err?.type === 'entity.parse.failed') {
    error = ApiError.badRequest('The request body is not valid JSON.', 'invalid_json');
  }
  if (!error && err?.type === 'entity.too.large') {
    error = new ApiError(413, 'payload_too_large', 'The request is too large.');
  }
  if (!error && err?.code && typeof err.code === 'string') {
    error = fromSupabaseError(err);
  }
  if (!error) {
    error = new ApiError(500, 'internal_error', 'Something went wrong. Please try again.');
    error.cause = err;
  }

  if (error.status >= 500 && error.status !== 501) {
    console.error(`[${req.id}] ${req.method} ${req.originalUrl} failed:`, error.cause ?? err);
  }

  const body = { error: { code: error.code, message: error.message } };
  if (error.details) body.error.details = error.details;
  if (!isProduction && error.status >= 500 && error.cause) {
    body.error.debug = String(error.cause?.message ?? error.cause);
  }
  body.error.requestId = req.id;
  res.status(error.status).json(body);
}
