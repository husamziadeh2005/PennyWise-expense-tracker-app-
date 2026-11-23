import { ApiError } from '../lib/errors.js';

/**
 * validate({ body, query, params }) — checks the request against zod
 * schemas BEFORE the route runs. If anything is wrong the client gets a
 * 400 with a list of problems, e.g.
 *
 *   { "error": { "code": "validation_failed",
 *                "message": "amount: Amount must be greater than 0",
 *                "details": [{ "field": "amount", "message": "..." }] } }
 *
 * The cleaned, typed values are stored on req.valid.body / .query / .params
 * (unknown fields are dropped, so a client can never sneak in "user_id").
 */
export function validate(schemas) {
  return (req, res, next) => {
    req.valid = {};
    const problems = [];
    for (const part of ['params', 'query', 'body']) {
      const schema = schemas[part];
      if (!schema) continue;
      const result = schema.safeParse(req[part] ?? {});
      if (result.success) {
        req.valid[part] = result.data;
      } else {
        for (const issue of result.error.issues) {
          problems.push({ field: issue.path.join('.') || part, message: issue.message });
        }
      }
    }
    if (problems.length) {
      const first = problems[0];
      return next(
        ApiError.badRequest(`${first.field}: ${first.message}`, 'validation_failed', problems),
      );
    }
    return next();
  };
}
