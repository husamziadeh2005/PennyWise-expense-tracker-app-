import { Router } from 'express';
import { validate } from '../middleware/validate.js';
import { statsSchemas } from '../schemas/index.js';
import { getMonthlySummary } from '../services/stats.service.js';

const router = Router();

// GET /api/stats/summary?month=2026-11&today=2026-11-19
router.get('/summary', validate({ query: statsSchemas.summary }), async (req, res) => {
  res.json(await getMonthlySummary(req.supabase, req.valid.query));
});

export default router;
