---
name: security
unit: boundary
enumerate: |
  A unit is a trust boundary, an untrusted input sink, an authentication or
  authorization gate, or a privileged execution surface. Most security
  reviews fail by skimming the happy-path handler and missing the adjacent
  route, the symlink hop, or the fallback path that fails open.

  Work in four sweeps.

  Sweep 1 - untrusted entry points (HTTP routes, RPC handlers, CLI flags,
  webhooks, file uploads, and message consumers).
  rg -n -i 'router\.(get|post|put|patch|delete)|app\.(get|post|put|delete)\(' .
  rg -n '@(Get|Post|Put|Patch|Delete)Mapping|@app\.route|def (get|post)' .
  rg -n -i 'webhook|signature|rawBody|multipart|upload' -g '!node_modules' .

  Sweep 2 - filesystem, path resolution, and process execution sinks.
  rg -n 'readFile|writeFile|createReadStream|unlink|rmdir|rmSync|realpath|lstat' \
    -g '!node_modules' .
  rg -n 'execFile|spawnSync|child_process|subprocess|os\.system' \
    -g '!node_modules' .

  Sweep 3 - authentication, session state, permissions, and secret handling.
  rg -n -i 'verify|jwt|session|cookie|authorize|permission|role|csrf|cors' \
    -g '!node_modules' .
  rg -o -I -N 'process\.env\.[A-Za-z_][A-Za-z0-9_]*' . | sort -u

  Sweep 4 - error handling and fallback paths (where fail-open bugs hide).
  rg -n 'catch\s*\(|except\s|recover\(' -g '!node_modules' .
dimensions: [trust-boundaries, input-validation, auth-and-authz, path-and-command-safety, secret-hygiene, fail-closed-defaults]
scale:
  1: broken - exploitable bypass, injection, traversal, or fail-open path in reachable code
  2: bad - missing validation or weak boundary check that relies on caller discipline
  3: acceptable - boundary holds on known inputs but lacks defense-in-depth or explicit tests
  4: good - validated at the boundary, least-privilege by default, and covered by negative tests
  5: exemplary - fail-closed across every path component, symlink, error branch, and edge case
---

# The security lens

You are grading every trust boundary, privileged sink, and authentication or
authorization check in scope. Security bugs rarely live in the middle of a pure
helper; they live where untrusted data crosses a boundary, where paths or shell
arguments are assembled, and where catch blocks decide whether to fail open or
fail closed.

## What a unit is

1. **Entry boundaries**: routes, webhook receivers, RPC methods, CLI parsers,
   and Deserialization points where untrusted input enters the system.
2. **Privileged sinks**: filesystem writes/reads, path containment checks,
   process spawns, SQL/database queries, and outbound network requests.
3. **Auth and session gates**: token verification, permission middleware, tenant
   isolation filters, and secret/credential loaders.

## How to grade each dimension

- `trust-boundaries`: Is untrusted input separated cleanly from validated domain
  data, or do downstream functions re-parse raw strings?
- `input-validation`: Are types, lengths, schemes, and allowlists enforced before
  any side effect runs?
- `auth-and-authz`: Does every state-changing or data-reading route verify both
  identity (authentication) and resource ownership/role (authorization)?
- `path-and-command-safety`: Are filesystem paths canonicalized and checked walk
  by walk (including parent symlink hops and trailing slashes), and are process
  invocations passed as argument arrays without shell interpolation?
- `secret-hygiene`: Are tokens, keys, and credentials kept out of logs, error
  messages, URLs, and client bundles, and compared in constant time where
  applicable?
- `fail-closed-defaults`: When a lookup, parse, stat, or verification step
  throws or returns null, does the guard deny access (`fail closed`) or silently
  allow execution (`fail open`)?
