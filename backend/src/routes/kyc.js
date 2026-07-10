// src/routes/kyc.js
// Handles KYC document upload: file goes to Supabase Storage, metadata
// row goes to core.kyc_documents. The actual bytes never pass through
// PostgREST/PostgreSQL — only the storage_bucket/storage_object_key
// reference does.
const express = require('express');
const multer = require('multer');
const crypto = require('crypto');
const { query } = require('./../db');
const { uploadObject } = require('./../services/supabaseStorage');
const { requireAuth } = require('./../middleware/auth');
const config = require('./../config');

const router = express.Router();
const upload = multer({
    storage: multer.memoryStorage(),
    limits: { fileSize: 10 * 1024 * 1024 }, // 10MB max per document
});

const ALLOWED_DOCUMENT_TYPES = ['ID_PROOF', 'ADDRESS_PROOF', 'PHOTO', 'SIGNATURE', 'OTHER'];
const ALLOWED_MIME_TYPES = ['image/jpeg', 'image/png', 'application/pdf'];

/**
 * POST /kyc/documents
 * multipart/form-data: file, kycCaseId, documentType
 * Staff or the owning customer may upload.
 */
router.post('/documents', requireAuth, upload.single('file'), async (req, res) => {
    const { kycCaseId, documentType } = req.body;

    if (!req.file) {
        return res.status(400).json({ error: 'No file uploaded (field name must be "file")' });
    }
    if (!kycCaseId || !documentType) {
        return res.status(400).json({ error: 'kycCaseId and documentType are required' });
    }
    if (!ALLOWED_DOCUMENT_TYPES.includes(documentType)) {
        return res.status(400).json({ error: `documentType must be one of: ${ALLOWED_DOCUMENT_TYPES.join(', ')}` });
    }
    if (!ALLOWED_MIME_TYPES.includes(req.file.mimetype)) {
        return res.status(400).json({ error: `File type ${req.file.mimetype} is not allowed` });
    }

    // Authorization: the caller must either be staff, or the customer who
    // owns this KYC case. RLS on core.kyc_cases already enforces this for
    // reads via PostgREST, but this endpoint bypasses PostgREST (it needs
    // the file bytes), so we re-check ownership explicitly here.
    const caseCheck = await query(
        `SELECT kc.id
         FROM core.kyc_cases kc
         JOIN core.customers c ON c.id = kc.customer_id
         WHERE kc.id = $1 AND (c.auth_subject_id = $2 OR $3 IN ('web_staff', 'web_admin'))`,
        [kycCaseId, req.user.sub, req.user.role]
    );

    if (caseCheck.rows.length === 0) {
        return res.status(403).json({ error: 'Not authorized to upload documents for this KYC case' });
    }

    const objectKey = `${kycCaseId}/${crypto.randomUUID()}-${req.file.originalname}`;
    await uploadObject(config.storage.buckets.kyc, objectKey, req.file.buffer, req.file.mimetype);

    const uploadedByCustomer = req.user.role === 'web_customer';

    const result = await query(
        `INSERT INTO core.kyc_documents
            (kyc_case_id, document_type, storage_bucket, storage_object_key, original_filename, uploaded_by_customer)
         VALUES ($1, $2, $3, $4, $5, $6)
         RETURNING id, document_type, original_filename, status, uploaded_at`,
        [kycCaseId, documentType, config.storage.buckets.kyc, objectKey, req.file.originalname, uploadedByCustomer]
    );

    res.status(201).json({ document: result.rows[0] });
});

module.exports = router;
