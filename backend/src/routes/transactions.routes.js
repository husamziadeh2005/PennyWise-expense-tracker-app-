import { Router } from 'express';
import { validate } from '../middleware/validate.js';
import { uploadLimiter } from '../middleware/rateLimit.js';
import { readUploadedFile, singleFileUpload } from '../lib/files.js';
import { idParams, transactionSchemas } from '../schemas/index.js';
import * as transactions from '../services/transactions.service.js';

const router = Router();

const RECEIPT_TYPES = ['image/jpeg', 'image/png', 'image/webp', 'image/heic', 'application/pdf'];

// GET /api/transactions?from=&to=&type=&categoryId=&q=&limit=&offset=
router.get('/', validate({ query: transactionSchemas.list }), async (req, res) => {
  res.json(await transactions.listTransactions(req.supabase, req.valid.query));
});

// GET /api/transactions/:id
router.get('/:id', validate({ params: idParams }), async (req, res) => {
  res.json(await transactions.getTransaction(req.supabase, req.valid.params.id));
});

// POST /api/transactions  { type, amount, categoryId?, note?, occurredOn? }
router.post('/', validate({ body: transactionSchemas.create }), async (req, res) => {
  res.status(201).json(await transactions.createTransaction(req.supabase, req.valid.body));
});

// PATCH /api/transactions/:id  (any subset of the fields above)
router.patch('/:id', validate({ params: idParams, body: transactionSchemas.update }), async (req, res) => {
  res.json(await transactions.updateTransaction(req.supabase, req.valid.params.id, req.valid.body));
});

// DELETE /api/transactions/:id  (also deletes its receipt file)
router.delete('/:id', validate({ params: idParams }), async (req, res) => {
  res.json(await transactions.deleteTransaction(req.supabase, req.valid.params.id));
});

// ----------------------------------------------------------------- receipts

// PUT /api/transactions/:id/receipt   multipart/form-data, field "file"
router.put(
  '/:id/receipt',
  uploadLimiter,
  validate({ params: idParams }),
  singleFileUpload({ maxBytes: 5 * 1024 * 1024 }),
  async (req, res) => {
    const file = readUploadedFile(req, RECEIPT_TYPES);
    res.json(await transactions.attachReceipt(req.supabase, req.user.id, req.valid.params.id, file));
  },
);

// GET /api/transactions/:id/receipt  -> { url, expiresIn }  (temporary link)
router.get('/:id/receipt', validate({ params: idParams }), async (req, res) => {
  res.json(await transactions.getReceiptUrl(req.supabase, req.valid.params.id));
});

// DELETE /api/transactions/:id/receipt
router.delete('/:id/receipt', validate({ params: idParams }), async (req, res) => {
  res.json(await transactions.removeReceipt(req.supabase, req.valid.params.id));
});

export default router;
