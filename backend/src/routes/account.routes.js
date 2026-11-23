import { Router } from 'express';
import { deleteAccount, resetMyData } from '../services/account.service.js';

const router = Router();

// POST /api/account/reset  -> wipes transactions, budgets and categories
router.post('/reset', async (req, res) => {
  res.json(await resetMyData(req.supabase, req.user.id));
});

// DELETE /api/account  -> permanently deletes the user (needs SUPABASE_SECRET_KEY)
router.delete('/', async (req, res) => {
  res.json(await deleteAccount(req.supabase, req.user.id));
});

export default router;
