-- Static same-origin explorer assets, embedded as Lua strings (ADR-01): no dependency on
-- files being present on disk/package.path, identical behavior in CGI (new process per
-- request) and `guaraci dev` (reload). M.html has no inline <script> and no dynamic data
-- interpolation at all (ADR-02, §5.6): every piece of catalog data enters via fetch() + DOM
-- APIs inside M.js, never via string concatenation into HTML.
local M = {}

M.html = [==[<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Guaraci API Explorer</title>
<link rel="stylesheet" href="/__guaraci/explorer/style.css">
</head>
<body>
<header>
<h1>Guaraci API Explorer</h1>
</header>
<main>
<section id="controls" aria-label="Filters">
<label for="method-filter">Method</label>
<select id="method-filter">
<option value="">All methods</option>
<option value="GET">GET</option>
<option value="POST">POST</option>
<option value="PUT">PUT</option>
<option value="PATCH">PATCH</option>
<option value="DELETE">DELETE</option>
<option value="HEAD">HEAD</option>
</select>
<label for="path-filter">Search</label>
<input type="search" id="path-filter" placeholder="Filter by path, name or summary">
</section>
<section id="operations" aria-label="Operations">
<ul id="operation-list"></ul>
</section>
<section id="response" aria-label="Response" hidden>
<h2>Response</h2>
<dl id="response-meta"></dl>
<pre id="response-body"></pre>
</section>
</main>
<script src="/__guaraci/explorer/app.js"></script>
</body>
</html>
]==]

M.css = [==[:root {
    color-scheme: light dark;
}

body {
    font-family: system-ui, -apple-system, "Segoe UI", Roboto, sans-serif;
    margin: 0;
    padding: 1rem;
    color: #1a1a1a;
    background: #ffffff;
    line-height: 1.4;
}

header h1 {
    font-size: 1.25rem;
    margin: 0 0 1rem;
}

#controls {
    display: flex;
    gap: 0.75rem;
    margin-bottom: 1rem;
    flex-wrap: wrap;
    align-items: center;
}

#controls label {
    font-weight: 600;
}

#controls select,
#controls input {
    font-size: 1rem;
    padding: 0.25rem 0.4rem;
}

#operation-list {
    list-style: none;
    margin: 0;
    padding: 0;
}

.operation {
    border: 1px solid #ccc;
    border-radius: 4px;
    padding: 0.5rem 0.75rem;
    margin-bottom: 0.5rem;
}

.operation-header {
    display: flex;
    gap: 0.5rem;
    align-items: baseline;
    flex-wrap: wrap;
}

.method {
    font-weight: 700;
    padding: 0.1rem 0.4rem;
    border-radius: 3px;
    color: #ffffff;
    background: #555555;
    font-size: 0.85rem;
}

.method-get {
    background: #1d4ed8;
}

.method-post {
    background: #15803d;
}

.method-put {
    background: #b45309;
}

.method-patch {
    background: #7e22ce;
}

.method-delete {
    background: #b91c1c;
}

.method-head {
    background: #374151;
}

.path {
    font-family: ui-monospace, Menlo, Consolas, monospace;
}

.operation-id,
.summary {
    color: #333333;
}

.params {
    list-style: none;
    margin: 0.4rem 0 0;
    padding: 0;
    display: flex;
    flex-wrap: wrap;
    gap: 0.4rem;
}

.param {
    font-size: 0.85rem;
    border: 1px solid #ddd;
    border-radius: 3px;
    padding: 0.1rem 0.4rem;
    display: inline-flex;
    gap: 0.3rem;
}

.param-required {
    color: #b91c1c;
    font-weight: 600;
}

.empty,
.error {
    font-style: italic;
    color: #555555;
}

#response {
    margin-top: 1.5rem;
    border-top: 1px solid #ccc;
    padding-top: 1rem;
}

#response-body {
    white-space: pre-wrap;
    word-break: break-word;
    background: #f5f5f5;
    padding: 0.75rem;
    border-radius: 4px;
}

#response-meta {
    display: grid;
    grid-template-columns: max-content 1fr;
    gap: 0.2rem 0.75rem;
    margin: 0 0 0.75rem;
}

#response-meta dt {
    font-weight: 600;
}

#response-meta dd {
    margin: 0;
    font-family: ui-monospace, Menlo, Consolas, monospace;
}

.status-ok {
    color: #15803d;
}

.status-error {
    color: #b91c1c;
}

.try-form {
    margin-top: 0.6rem;
    display: flex;
    flex-wrap: wrap;
    gap: 0.5rem;
    align-items: end;
}

.try-form .field {
    display: flex;
    flex-direction: column;
    font-size: 0.85rem;
    gap: 0.15rem;
}

.try-form input,
.try-form textarea {
    font-size: 0.9rem;
    padding: 0.2rem 0.3rem;
}

.try-form textarea {
    font-family: ui-monospace, Menlo, Consolas, monospace;
    min-width: 16rem;
}

.form-error {
    color: #b91c1c;
    margin: 0;
    width: 100%;
}
]==]

M.js = [==[(function () {
    "use strict";

    var catalog = [];

    function flattenOperations(doc) {
        var ops = [];
        var paths = (doc && doc.paths) || {};
        Object.keys(paths).forEach(function (path) {
            var methods = paths[path];
            Object.keys(methods).forEach(function (method) {
                ops.push({ path: path, method: method.toUpperCase(), operation: methods[method] });
            });
        });
        return ops;
    }

    function matchesFilter(op, methodFilter, textFilter) {
        if (methodFilter && op.method !== methodFilter) {
            return false;
        }
        if (!textFilter) {
            return true;
        }
        var haystack = (
            op.path + " " +
            (op.operation.operationId || "") + " " +
            (op.operation.summary || "")
        ).toLowerCase();
        return haystack.indexOf(textFilter.toLowerCase()) !== -1;
    }

    function createParamRow(param) {
        var li = document.createElement("li");
        li.className = "param";

        var name = document.createElement("span");
        name.className = "param-name";
        name.textContent = param.name;
        li.appendChild(name);

        var loc = document.createElement("span");
        loc.className = "param-in";
        loc.textContent = "(" + param["in"] + ")";
        li.appendChild(loc);

        if (param.required) {
            var req = document.createElement("span");
            req.className = "param-required";
            req.textContent = "required";
            li.appendChild(req);
        }

        return li;
    }

    var UNSAFE_METHODS = { POST: true, PUT: true, PATCH: true, DELETE: true };

    function readCookie(name) {
        var match = document.cookie.match(new RegExp("(?:^|; )" + name + "=([^;]*)"));
        return match ? decodeURIComponent(match[1]) : null;
    }

    function clearNode(node) {
        while (node.firstChild) {
            node.removeChild(node.firstChild);
        }
    }

    function buildUrl(op, values) {
        var path = op.path.replace(/\{([^}]+)\}/g, function (_, name) {
            return encodeURIComponent(values.path[name] || "");
        });
        var query = [];
        Object.keys(values.query).forEach(function (name) {
            var value = values.query[name];
            if (value !== "") {
                query.push(encodeURIComponent(name) + "=" + encodeURIComponent(value));
            }
        });
        return query.length > 0 ? path + "?" + query.join("&") : path;
    }

    function addMetaRow(dl, name, value, className) {
        var dt = document.createElement("dt");
        dt.textContent = name;
        dl.appendChild(dt);
        var dd = document.createElement("dd");
        dd.textContent = value;
        if (className) {
            dd.className = className;
        }
        dl.appendChild(dd);
    }

    function renderResponse(status, headers, bodyText) {
        var section = document.getElementById("response");
        section.hidden = false;

        var meta = document.getElementById("response-meta");
        clearNode(meta);
        addMetaRow(meta, "Status", String(status), status >= 200 && status < 300 ? "status-ok" : "status-error");
        headers.forEach(function (value, name) {
            addMetaRow(meta, name, value);
        });

        var pretty = bodyText;
        try {
            pretty = JSON.stringify(JSON.parse(bodyText), null, 2);
        } catch (parseErr) {
            pretty = bodyText;
        }
        document.getElementById("response-body").textContent = pretty;
    }

    function renderNetworkError(err) {
        var section = document.getElementById("response");
        section.hidden = false;
        var meta = document.getElementById("response-meta");
        clearNode(meta);
        addMetaRow(meta, "Error", "Network error", "status-error");
        document.getElementById("response-body").textContent = String((err && err.message) || err);
    }

    // The server's CGI adapter only decodes application/x-www-form-urlencoded (and
    // multipart) bodies into req.body_table; there is no JSON request-body decoder anywhere
    // in the framework (confirmed by reading adapter_cgi.lua and json_util.lua), so a raw
    // application/json request would never reach the generated route's validation/auto_crud
    // handler at all. The JSON editor still validates the payload as a JSON object
    // client-side (required by this story), but it is transmitted as top-level form fields
    // the server already knows how to parse; a nested value is re-serialized with
    // JSON.stringify, matching the documented "table" field contract (the column stores the
    // JSON-encoded string, not a nested object).
    function encodeFormBody(fields) {
        return Object.keys(fields).map(function (key) {
            var value = fields[key];
            var text = (typeof value === "object" && value !== null) ? JSON.stringify(value) : String(value);
            return encodeURIComponent(key) + "=" + encodeURIComponent(text);
        }).join("&");
    }

    function sendRequest(op, values, body) {
        var headers = {};
        var fetchOpts = { method: op.method, credentials: "same-origin", headers: headers };

        if (body !== null) {
            headers["Content-Type"] = "application/x-www-form-urlencoded";
            fetchOpts.body = encodeFormBody(body);
        }

        if (UNSAFE_METHODS[op.method]) {
            var token = readCookie("guaraci_csrf_token");
            if (token) {
                headers["X-CSRF-Token"] = token;
            }
        }

        fetch(buildUrl(op, values), fetchOpts)
            .then(function (res) {
                return res.text().then(function (text) {
                    renderResponse(res.status, res.headers, text);
                });
            })
            .catch(renderNetworkError);
    }

    function createFieldInput(param, kind) {
        var label = document.createElement("label");
        label.className = "field";

        var text = document.createElement("span");
        text.textContent = param.name + (param.required ? " *" : "");
        label.appendChild(text);

        var input = document.createElement("input");
        input.type = "text";
        input.dataset.paramName = param.name;
        input.dataset.paramKind = kind;
        label.appendChild(input);

        return label;
    }

    function createTryForm(op) {
        var form = document.createElement("form");
        form.className = "try-form";

        var pathParams = (op.operation.parameters || []).filter(function (p) { return p["in"] === "path"; });
        var queryParams = (op.operation.parameters || []).filter(function (p) { return p["in"] === "query"; });
        var hasBody = Boolean(op.operation.requestBody);

        pathParams.concat(queryParams).forEach(function (param) {
            form.appendChild(createFieldInput(param, param["in"]));
        });

        var bodyField = null;
        if (hasBody) {
            var bodyLabel = document.createElement("label");
            bodyLabel.className = "field";
            var bodyText = document.createElement("span");
            bodyText.textContent = "JSON body";
            bodyLabel.appendChild(bodyText);
            bodyField = document.createElement("textarea");
            bodyField.rows = 4;
            bodyField.placeholder = "{}";
            bodyLabel.appendChild(bodyField);
            form.appendChild(bodyLabel);
        }

        var error = document.createElement("p");
        error.className = "form-error";
        error.hidden = true;
        form.appendChild(error);

        var submit = document.createElement("button");
        submit.type = "submit";
        submit.textContent = "Send " + op.method;
        form.appendChild(submit);

        form.addEventListener("submit", function (event) {
            event.preventDefault();
            error.hidden = true;
            error.textContent = "";

            var values = { path: {}, query: {} };
            var missing = [];

            pathParams.forEach(function (param) {
                var input = form.querySelector(
                    'input[data-param-name="' + param.name + '"][data-param-kind="path"]');
                if (param.required && input.value === "") {
                    missing.push(param.name);
                }
                values.path[param.name] = input.value;
            });
            queryParams.forEach(function (param) {
                var input = form.querySelector(
                    'input[data-param-name="' + param.name + '"][data-param-kind="query"]');
                values.query[param.name] = input.value;
            });

            if (missing.length > 0) {
                error.textContent = "Missing required field(s): " + missing.join(", ");
                error.hidden = false;
                return;
            }

            var bodyRaw = bodyField ? bodyField.value.trim() : "";
            var parsedBody = null;
            if (bodyRaw !== "") {
                try {
                    parsedBody = JSON.parse(bodyRaw);
                } catch (parseErr) {
                    error.textContent = "Invalid JSON body: " + parseErr.message;
                    error.hidden = false;
                    return;
                }
                if (typeof parsedBody !== "object" || parsedBody === null || Array.isArray(parsedBody)) {
                    error.textContent = "JSON body must be an object";
                    error.hidden = false;
                    return;
                }
            }

            sendRequest(op, values, parsedBody);
        });

        return form;
    }

    function createOperationItem(op) {
        var li = document.createElement("li");
        li.className = "operation";

        var header = document.createElement("div");
        header.className = "operation-header";

        var method = document.createElement("span");
        method.className = "method method-" + op.method.toLowerCase();
        method.textContent = op.method;
        header.appendChild(method);

        var path = document.createElement("span");
        path.className = "path";
        path.textContent = op.path;
        header.appendChild(path);

        if (op.operation.summary) {
            var summary = document.createElement("span");
            summary.className = "summary";
            summary.textContent = op.operation.summary;
            header.appendChild(summary);
        }

        if (op.operation.operationId) {
            var opId = document.createElement("span");
            opId.className = "operation-id";
            opId.textContent = op.operation.operationId;
            header.appendChild(opId);
        }

        li.appendChild(header);

        var params = (op.operation.parameters || []);
        if (params.length > 0) {
            var list = document.createElement("ul");
            list.className = "params";
            params.forEach(function (param) {
                list.appendChild(createParamRow(param));
            });
            li.appendChild(list);
        }

        li.appendChild(createTryForm(op));

        return li;
    }

    function render() {
        var list = document.getElementById("operation-list");
        clearNode(list);

        var methodFilter = document.getElementById("method-filter").value;
        var textFilter = document.getElementById("path-filter").value;

        var visible = catalog.filter(function (op) {
            return matchesFilter(op, methodFilter, textFilter);
        });

        if (visible.length === 0) {
            var empty = document.createElement("li");
            empty.className = "empty";
            empty.textContent = "No operations match the current filters.";
            list.appendChild(empty);
            return;
        }

        visible.forEach(function (op) {
            list.appendChild(createOperationItem(op));
        });
    }

    function showLoadError() {
        var list = document.getElementById("operation-list");
        clearNode(list);
        var li = document.createElement("li");
        li.className = "error";
        li.textContent = "Failed to load the API catalog.";
        list.appendChild(li);
    }

    function loadCatalog() {
        fetch("/__guaraci/api-docs", { credentials: "same-origin" })
            .then(function (res) {
                if (!res.ok) {
                    throw new Error("api-docs responded with " + res.status);
                }
                return res.json();
            })
            .then(function (doc) {
                catalog = flattenOperations(doc);
                render();
            })
            .catch(showLoadError);
    }

    document.addEventListener("DOMContentLoaded", function () {
        loadCatalog();
        document.getElementById("method-filter").addEventListener("change", render);
        document.getElementById("path-filter").addEventListener("input", render);
    });
})();
]==]

return M
