import { Router } from 'express';
import { validate } from '../middleware/validate.js';
import { uploadLimiter } from '../middleware/rateLimit.js';
import { readUploadedFile, singleFileUpload } from '../lib/files.js';
import { profileSchemas } from '../schemas/index.js';
import * as profile from '../services/profile.service.js';

const router = Router();

// GET /api/profile
router.get('/', async (req, res) => {
  res.json(await profile.getProfile(req.supabase, req.user.id));
});

// PATCH /api/profile  { fullName?, country?, gender?, currency? }
router.patch('/', validate({ body: profileSchemas.update }), async (req, res) => {
  res.json(await profile.updateProfile(req.supabase, req.user.id, req.valid.body));
});

// PUT /api/profile/avatar   multipart/form-data, field "file" (jpg/png/webp, max 2 MB)
router.put('/avatar', uploadLimiter, singleFileUpload({ maxBytes: 2 * 1024 * 1024 }), async (req, res) => {
  const file = readUploadedFile(req, ['image/jpeg', 'image/png', 'image/webp']);
  res.json(await profile.uploadAvatar(req.supabase, req.user.id, file));
});

// DELETE /api/profile/avatar
router.delete('/avatar', async (req, res) => {
  res.json(await profile.removeAvatar(req.supabase, req.user.id));
});

export default router;
