// src/services/supabaseStorage.js
// Wraps Supabase Storage (service-role key, bypasses Storage RLS) for
// the two operations the backend needs: create buckets at startup if
// missing, and upload/sign KYC documents. Replaces minioClient.js.
const { supabaseAdmin } = require('./supabaseAdmin');
const config = require('./../config');

async function ensureBucketsExist() {
    const { data: existing, error: listError } = await supabaseAdmin.storage.listBuckets();
    if (listError) throw new Error(`Failed to list Storage buckets: ${listError.message}`);

    const existingNames = new Set((existing || []).map((b) => b.name));

    for (const bucket of Object.values(config.storage.buckets)) {
        if (!existingNames.has(bucket)) {
            // eslint-disable-next-line no-await-in-loop
            const { error } = await supabaseAdmin.storage.createBucket(bucket, { public: false });
            if (error) throw new Error(`Failed to create bucket "${bucket}": ${error.message}`);
            // eslint-disable-next-line no-console
            console.log(`Supabase Storage: created bucket "${bucket}"`);
        }
    }
}

async function uploadObject(bucket, objectKey, buffer, mimeType) {
    const { error } = await supabaseAdmin.storage
        .from(bucket)
        .upload(objectKey, buffer, { contentType: mimeType, upsert: false });
    if (error) throw new Error(`Storage upload failed: ${error.message}`);
}

async function getPresignedDownloadUrl(bucket, objectKey, expirySeconds = 300) {
    const { data, error } = await supabaseAdmin.storage
        .from(bucket)
        .createSignedUrl(objectKey, expirySeconds);
    if (error) throw new Error(`Failed to create signed URL: ${error.message}`);
    return data.signedUrl;
}

module.exports = { ensureBucketsExist, uploadObject, getPresignedDownloadUrl };
