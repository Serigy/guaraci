# Files

- [Data Layer](data-layer.md)
- [Error Handling](error-handling.md) - How Guaraci isolates pipeline failures, normalizes error payloads, masks internals in production, and negotiates JSON, XML, or HTML error bodies.
- [File Uploads](file-uploads.md) - How Guaraci parses multipart/form-data requests, validates MIME type and size, stores files through a pluggable provider registry, and cleans up per-request uploads.
- [Hooks and Audit](hooks-and-audit.md) - Hook stages, default security-headers loading, the middleware chain boundary, and JSONL audit logging with secret redaction.
- [Architecture Overview](overview.md)
- [Request Lifecycle](request-lifecycle.md)
- [Routing and Middleware](routing-middleware.md) - Explicit Gin-style routing with router_v2, prefixed route groups, the priority-ordered middleware chain, the request-scoped context store, and the deprecated file-system router.
- [Template Engine](template-engine.md)
- [Validation, Binding, and Security Middleware](validation-security-middleware.md) - Declarative schema validation, JSON/form binding with type coercion, and the native CORS, CSRF, and rate-limit security middlewares.
