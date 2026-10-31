---
type: architecture
title: File Uploads
description: How Guaraci parses multipart/form-data requests, validates MIME type and size, stores files through a pluggable provider registry, and cleans up per-request uploads.
tags: [lua, upload, multipart, mime, validation, storage, security]
---

# File Uploads

File uploads in Guaraci flow through four modules: `multipart` parses the request body, `file_validator` enforces MIME and size limits, `file_storage` provides pluggable storage backends, and `file_manager` orchestrates validation, storage, and per-request cleanup.

## Multipart parsing (`multipart`)

`multipart.parse(body, content_type)` accepts only `multipart/form-data` and requires a boundary. It scans the body for the boundary delimiter, splitting each part into its header block and payload. The `Content-Disposition` header determines whether a part is a file (has a `filename`) or a plain form field. File parts are collected into a `files` array with `field`, `filename`, `content_type`, `data`, and `size`; field parts land in `form_data`. `multipart.is_multipart(content_type)` lets callers branch before attempting a parse.

## Validation (`file_validator`)

Every upload passes `file_validator`, which enforces three limits by default: 25 MB per file, 200 MB total per payload, and a MIME allow-list (`image/jpeg`, `image/png`, `application/pdf`, `text/plain`). Before any other check, `sanitize_filename` rejects path traversal — `..` segments, a leading `/`, NUL bytes, names longer than 255 characters, and any character outside letters, digits, dot, underscore, hyphen, and slash (percent is not allowed). A file is rejected if its size exceeds the per-file limit or its MIME type is not allow-listed; `validate_payload` additionally rejects a batch whose cumulative size exceeds the payload cap.

## Storage (`file_storage`)

Storage is pluggable through a provider registry. `new_registry(default_provider)` holds named providers with `set_provider`, `use`, and `active`, and forwards `put`/`get`/`delete` to the active provider. The built-in local provider writes each file as `{random_id}_{sanitized filename}` under a configurable `root_dir` (default `uploads`, overridable with `GUARACI_UPLOAD_DIR`), and keeps an in-memory index of stored files for retrieval and deletion. The random id comes from `guaraci_random` (`/dev/urandom` with a seeded fallback), so ids are not predictable across CGI processes.

## Orchestration and cleanup (`file_manager`)

`file_manager.process_files(files, opts)` first runs the full payload through `file_validator` (logging a security event on rejection), then stores each file and records the returned metadata. When a `request_id` is supplied, the stored ids are indexed against it so `cleanup_request(request_id)` can delete every file from that request after the response, preventing orphaned uploads.

When validation fails, `handle_request` answers `413 Payload too large` for client size errors, `400 Invalid upload` for other client errors, and `500` for server-side storage failures; the raw reason is only exposed in `details` (dev) and in the audit log, never in the HTTP body. Each stored file is indexed as soon as it is written, so if a later file in a multi-file upload fails, the earlier files are cleaned up and no orphans remain.
