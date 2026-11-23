import { Router } from 'express';
import { validate } from '../middleware/validate.js';
import { budgetSchemas, idParams } from '../schemas/index.js';
import * as budgets from '../services/budgets.service.js';

const router = Router();

// GET /api/budgets
router.get('/', async (req, res) => {
  res.json({ items: await budgets.listBudgets(req.supabase) });
});

// POST /api/budgets  { categoryId: null | <expense category id>, amount }
router.post('/', validate({ body: budgetSchemas.create }), async (req, res) => {
  res.status(201).json(await budgets.createBudget(req.supabase, req.valid.body));
});

// PATCH /api/budgets/:id  { amount }
router.patch('/:id', validate({ params: idParams, body: budgetSchemas.update }), async (req, res) => {
  res.json(await budgets.updateBudget(req.supabase, req.valid.params.id, req.valid.body));
});

// DELETE /api/budgets/:id
router.delete('/:id', validate({ params: idParams }), async (req, res) => {
  res.json(await budgets.deleteBudget(req.supabase, req.valid.params.id));
});

export default router;
