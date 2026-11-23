/**
 * One error type for the whole API. Throw it anywhere in a route or
 * service; the error-handler middleware turns it into a JSON response:
 *
 *   { "error": { "code": "not_found", "message": "Transaction not found." } }
 *
 * `code` is stable and meant for the app's logic; `message` is for people.
 */
export class ApiError extends Error {
  constructor(status, code, message, details) {
    super(message);
    this.status = status;
    this.code = code;
    this.details = details;
  }

  static badRequest(message, code = 'bad_request', details) {
    return new ApiError(400, code, message, details);
  }
  static unauthorized(message = 'Please log in again.', code = 'unauthorized') {
    return new ApiError(401, code, message);
  }
  static forbidden(message = 'You are not allowed to do that.') {
    return new ApiError(403, 'forbidden', message);
  }
  static notFound(what = 'Resource') {
    return new ApiError(404, 'not_found', `${what} not found.`);
  }
  static conflict(message, code = 'conflict') {
    return new ApiError(409, code, message);
  }
}

// Messages for the custom errors raised by our database triggers/functions
// (the `hint` we set in SQL with RAISE ... USING hint = '...').
const DB_HINTS = {
  category_type_mismatch: [400, 'The category type must match the transaction type (income / expense).'],
  invalid_receipt_path: [400, 'Invalid receipt.'],
  budget_category_not_expense: [400, 'Budgets can only be set for expense categories.'],
  category_not_found: [404, 'Category not found.'],
  target_not_found: [404, 'The category to move transactions to was not found.'],
  same_category: [400, 'Choose a different category to move the transactions to.'],
};

/**
 * Converts a Supabase / PostgREST error into an ApiError with a correct
 * HTTP status. Postgres error codes: https://www.postgresql.org/docs/current/errcodes-appendix.html
 */
export function fromSupabaseError(error, { conflictMessage } = {}) {
  if (!error) return null;
  if (error instanceof ApiError) return error;

  const hint = error.hint && DB_HINTS[error.hint];
  if (hint) return new ApiError(hint[0], error.hint, hint[1]);

  switch (error.code) {
    case '23505': // unique_violation
      return ApiError.conflict(conflictMessage ?? 'This already exists.', 'already_exists');
    case '23503': // foreign_key_violation (e.g. category belongs to someone else)
      return ApiError.badRequest('The selected category does not exist.', 'invalid_reference');
    case '23514': // check_violation
    case '23502': // not_null_violation
    case '22001': // value too long
    case '22003': // numeric out of range
    case '22P02': // invalid text representation (bad uuid, etc.)
    case '22007': // invalid date
    case '22008':
      return ApiError.badRequest('Some of the values are not valid.', 'invalid_value');
    case '42501': // insufficient_privilege (RLS / grants)
      return ApiError.forbidden();
    case 'P0002':
    case 'PGRST116': // .single() found no rows
      return ApiError.notFound();
    case 'PGRST301':
    case 'PGRST302':
      return ApiError.unauthorized();
    default:
      break;
  }

  // Storage errors
  const status = Number(error.statusCode ?? error.status);
  if (status === 413) return new ApiError(413, 'file_too_large', 'The file is too large.');
  if (status === 404) return ApiError.notFound('File');

  const wrapped = new ApiError(500, 'internal_error', 'Something went wrong. Please try again.');
  wrapped.cause = error;
  return wrapped;
}

/**
 * Small helper so every database call reads the same way:
 *
 *   const rows = await unwrap(supabase.from('x').select());
 */
export async function unwrap(promise, options) {
  const { data, error } = await promise;
  if (error) throw fromSupabaseError(error, options);
  return data;
}
