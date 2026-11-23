import multer from 'multer';
import { randomUUID } from 'node:crypto';
import { ApiError } from './errors.js';

/**
 * Detects the real file type from its first bytes ("magic numbers").
 * The Content-Type sent by a client can be anything, so we never trust it.
 */
export function sniffMimeType(buffer) {
  if (!buffer || buffer.length < 12) return null;
  const hex = buffer.subarray(0, 12).toString('hex');
  const ascii = buffer.subarray(0, 12).toString('latin1');

  if (hex.startsWith('ffd8ff')) return 'image/jpeg';
  if (hex.startsWith('89504e470d0a1a0a')) return 'image/png';
  if (ascii.startsWith('RIFF') && ascii.slice(8, 12) === 'WEBP') return 'image/webp';
  if (ascii.startsWith('%PDF-')) return 'application/pdf';
  // HEIC/HEIF (iPhone photos): "....ftypheic" / "ftypheix" / "ftypmif1" ...
  if (ascii.slice(4, 8) === 'ftyp' && /^(heic|heix|hevc|heim|heis|mif1|msf1)$/.test(ascii.slice(8, 12))) {
    return 'image/heic';
  }
  return null;
}

const EXTENSIONS = {
  'image/jpeg': 'jpg',
  'image/png': 'png',
  'image/webp': 'webp',
  'image/heic': 'heic',
  'application/pdf': 'pdf',
};

/** Multer middleware keeping one file (field "file") in memory. */
export function singleFileUpload({ maxBytes }) {
  const upload = multer({
    storage: multer.memoryStorage(),
    limits: { fileSize: maxBytes, files: 1, fields: 5 },
  }).single('file');

  return (req, res, next) =>
    upload(req, res, (err) => {
      if (!err) return next();
      if (err.code === 'LIMIT_FILE_SIZE') {
        return next(new ApiError(413, 'file_too_large', `The file must be smaller than ${Math.round(maxBytes / 1048576)} MB.`));
      }
      return next(ApiError.badRequest('Could not read the uploaded file.', 'invalid_upload'));
    });
}

/**
 * Validates the uploaded file and returns { buffer, mimeType, extension }.
 * Throws a 400 error if the file is missing or not an allowed type.
 */
export function readUploadedFile(req, allowedTypes) {
  if (!req.file?.buffer?.length) {
    throw ApiError.badRequest('Please attach a file in the "file" field.', 'file_required');
  }
  const mimeType = sniffMimeType(req.file.buffer);
  if (!mimeType || !allowedTypes.includes(mimeType)) {
    throw ApiError.badRequest(
      `Unsupported file type. Allowed: ${allowedTypes.map((t) => EXTENSIONS[t]).join(', ')}.`,
      'unsupported_file_type',
    );
  }
  return { buffer: req.file.buffer, mimeType, extension: EXTENSIONS[mimeType] };
}

/** "<user id>/<prefix>-<random>.<ext>" — the folder is what Storage RLS checks. */
export const storagePath = (userId, prefix, extension) =>
  `${userId}/${prefix}-${randomUUID()}.${extension}`;
