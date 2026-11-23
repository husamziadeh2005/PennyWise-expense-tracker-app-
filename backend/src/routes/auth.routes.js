import { Router } from 'express';
import { getProfile } from '../services/profile.service.js';
import { accountDeletionEnabled } from '../services/account.service.js';

const router = Router();

/**
 * GET /api/auth/me
 * Confirms the token is valid and returns who is logged in + their
 * profile. The app calls it right after login.
 */
router.get('/me', async (req, res) => {
  const profile = await getProfile(req.supabase, req.user.id).catch(() => null);
  res.json({
    user: {
      id: req.user.id,
      email: req.user.email,
      phone: req.user.phone,
      provider: req.user.provider,
    },
    profile,
    features: { accountDeletion: accountDeletionEnabled() },
  });
});

export default router;
