import { Router } from 'express';
import { validate } from '../middleware/validate.js';
import { categorySchemas, idParams } from '../schemas/index.js';
import * as categories from '../services/categories.service.js';

const router = Router();

// GET /api/categories?type=expense
router.get('/', validate({ query: categorySchemas.list }), async (req, res) => {
  res.json({ items: await categories.listCategories(req.supabase, req.valid.query) });
});

// POST /api/categories  { name, type, icon?, color? }
router.post('/', validate({ body: categorySchemas.create }), async (req, res) => {
  res.status(201).json(await categories.createCategory(req.supabase, req.valid.body));
});

// PATCH /api/categories/:id  { name?, icon?, color? }
router.patch('/:id', validate({ params: idParams, body: categorySchemas.update }), async (req, res) => {
  res.json(await categories.updateCategory(req.supabase, req.valid.params.id, req.valid.body));
});

// DELETE /api/categories/:id?reassignTo=<other category id>
router.delete('/:id', validate({ params: idParams, query: categorySchemas.remove }), async (req, res) => {
  res.json(await categories.deleteCategory(req.supabase, req.valid.params.id, req.valid.query.reassignTo));
});

export default router;
