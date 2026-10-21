# Why IP Whitelisting Is Inadequate as a Security Control

When you host on Saas platforms such as netlify or vercel, many firewall protected services may block you and you think IP whitelist is a good solution . Here's why this is not a good security practice. The core problem is a category error: **IP whitelisting is an *identification* mechanism, not an *authentication* or *authorization* mechanism.** It answers "what network did this packet originate from?" — not "who is the caller?", "are they authorized?", or "has the payload been tampered with?" Every bypass below exploits this gap.

---

## 1. Shared infrastructure makes the whitelist porous

Netlify Functions run on **AWS Lambda**, and Lambda egress IPs are drawn from AWS's shared regional NAT pools. Those addresses are used by:

- every other Netlify customer's functions,
- every other AWS Lambda customer in that region,
- any AWS service with a NAT Gateway in the same subnet ranges.

Netlify does **not** publish a stable, dedicated egress IP list for Functions, and even if it did, that list would be AWS's shared Lambda egress pool. AWS explicitly documents that Lambda egress IPs are **dynamic and shared**, and recommends a NAT Gateway with an Elastic IP only if you need a stable address — which is exactly the AWS/Azure public-IP architecture you're trying to avoid.

**Consequence:** "Whitelist Netlify's IPs" effectively means "whitelist a large slice of the AWS Lambda ecosystem." The whitelist stops being a security boundary and becomes an open door with a sign on it.

### Attack: free-tier tenant abuse

1. Attacker signs up for a free Netlify account (or any AWS account in the whitelisted region).
2. Deploys a one-line function that calls Freshdesk.
3. The request originates from the **same egress IP range** the WAF trusts.
4. The WAF allows it.

The attacker is now "inside" the perimeter without ever spoofing anything. They can enumerate ticket IDs, probe rate limits, brute-force endpoints, or use Freshdesk as a launchpad for further SSRF-style probing — limited only by Freshdesk's *own* auth, not by your IP rule.

This is the single most important bypass, and it requires no exotic technique.

---

## 2. SSRF turns any whitelisted host into a proxy

If **any** application hosted in the whitelisted range has a server-side request forgery vulnerability, the attacker can make that host issue requests to Freshdesk on their behalf. The request legitimately comes from the whitelisted IP, carries whatever headers the vulnerable app adds, and the WAF sees a trusted source.

Common SSRF surfaces:

- URL-fetching features (image previews, webhooks, PDF renderers, RSS importers).
- Open redirects chained with server-side fetchers.
- Misconfigured `fetch()` / `requests.get()` calls that accept user-controlled URLs.
- Metadata-service access paths (169.254.169.254) that lead to credential theft, then onward API calls.

Because Netlify/AWS egress is shared, the attacker doesn't even need *your* app to be vulnerable — any vulnerable tenant in the same egress pool works.

---

## 3. BGP hijacking and route manipulation

IP whitelisting trusts the **routing system** to deliver packets only from the legitimate owner of that prefix. BGP has no built-in cryptographic origin validation at internet scale (RPKI is partial and not universally deployed). Attackers — or misconfigured ISPs — can announce a more-specific prefix for the whitelisted range and attract traffic.

- A nation-state or large ISP-level actor can hijack the prefix and receive Freshdesk's replies.
- More commonly, **route leaks** cause traffic to transit unintended networks, where it can be observed.

This is rare but real (e.g., the 2008 Pakistan Telecom/YouTube hijack, the 2018 Amazon Route 53 hijack, the 2021 Facebook outage caused by BGP withdrawal). Whitelisting assumes the routing layer is trustworthy; it is not.

---

## 4. On-path MITM and compromised intermediaries

If an attacker controls any hop between the whitelisted egress and Freshdesk — a compromised router, a malicious ISP, a TLS-terminating middlebox, a corporate proxy — they can:

- observe the traffic (confidentiality loss),
- inject or modify packets (integrity loss),
- replay captured requests (replay attack, unless timestamps/nonces are enforced).

The source IP is still the whitelisted one. The whitelist does nothing here; only **TLS plus application-layer signing/nonces** defends against this.

---

## 5. Header spoofing if the WAF trusts forwarding headers

Many WAFs and origin servers derive the "client IP" from `X-Forwarded-For`, `X-Real-IP`, `Forwarded`, or `CF-Connecting-IP`. If Freshdesk's WAF (or any intermediary) trusts a client-supplied forwarding header rather than the actual TCP source address, an attacker can simply send:

```
X-Forwarded-For: <your-whitelisted-IP>
```

and the WAF will believe the request came from you. This is a misconfiguration, but it is common. Any IP-whitelisting design must verify that the enforcement point reads the **TCP source**, not a header.

---

## 6. Compromise of a legitimate host in the whitelisted range

Even a **static, dedicated** IP is only as trustworthy as every process that can send from it:

- **Insider threat** — an employee or contractor with access to the proxy host.
- **Supply-chain compromise** — a malicious npm package, a poisoned container image, a compromised CI/CD pipeline that deploys code to the proxy.
- **Credential theft** — stolen SSH keys, cloud IAM keys, or deployment tokens.
- **Lateral movement** — an attacker who compromises any service in the same VPC/subnet and pivots to the proxy.

The IP is still "correct." The whitelist cannot distinguish a legitimate request from a malicious one issued by code running on the trusted host.

---

## 7. Cloud IP reassignment and lifecycle drift

Cloud providers reassign elastic IPs and NAT addresses over time:

- An IP released by your account can be **reallocated to another AWS customer**.
- A region's NAT pool can change.
- IPv6 ranges are often less monitored and less consistently firewalled.

If your whitelist is static but the provider's assignment is dynamic, you eventually either (a) block yourself, or (b) whitelist an address that now belongs to someone else.

---

## 8. What IP whitelisting fails to provide

Whitelisting provides **none** of the core security properties:

| Property | What it requires | Does whitelisting provide it? |
|---|---|---|
| **Authentication** (who is calling?) | Credentials, tokens, certificates | ❌ No — only "where from" |
| **Authorization** (may they do this?) | Scopes, roles, policy | ❌ No |
| **Confidentiality** (no snooping) | TLS / encryption | ❌ No |
| **Integrity** (no tampering) | Signatures, MACs, TLS | ❌ No |
| **Replay protection** | Nonces, timestamps, short expiry | ❌ No |
| **Non-repudiation** | Signatures with keys | ❌ No |
| **Rate limiting / abuse control** | Quotas, anomaly detection | ❌ No |
| **Least privilege** | Scoped credentials | ❌ No |

An attacker who is "inside" the whitelist has **full, unauthenticated access** to whatever the protected service exposes. The whitelist is a single bit of trust: inside or outside. There is no notion of "how much" or "for what."

---

## 9. The castle-and-moat fallacy

IP whitelisting is a perimeter control. Perimeter controls assume:

> "If you're inside the network, you're trusted."

Modern attacks routinely defeat this assumption via:

- **Multi-tenancy** (shared cloud egress — §1)
- **SSRF and pivot** (§2)
- **Supply chain** (§6)
- **Credential theft** (§6)
- **Routing compromise** (§3)

Once any of these succeeds, the attacker has the same trust level as your legitimate app. There is no second check.

Zero-trust architecture inverts this: **authenticate and authorize every request, regardless of source network.** The network location is treated as untrusted metadata, not as a credential.

---

## 10. What IP whitelisting *is* good for

To be fair, whitelisting is not worthless. It is useful as **defense-in-depth**:

- It **reduces attack surface** — fewer scanners, bots, and opportunistic probes reach the service.
- It **adds a hurdle** — attackers must first obtain an IP in the trusted range (via free-tier signup, SSRF, or compromise).
- It is **cheap** and **simple** for low-risk, low-traffic admin interfaces.

But it must **never** be the sole control. It belongs in a layered design alongside:

- TLS with certificate validation (and pinning where possible).
- Short-lived, scoped tokens (JWT/OAuth) for service-to-service auth.
- mTLS for mutual authentication if the counterparty supports it.
- HMAC signatures with timestamps/nonces for integrity and replay protection.
- Rate limiting and anomaly detection.
- Secret management and rotation.
- Least-privilege API keys scoped to specific endpoints/actions.

---

## Bottom line

IP whitelisting answers **"where"**, not **"who"** or **"may they."** It is porous because cloud egress is shared, because SSRF and supply-chain compromise let attackers borrow the trusted IP, because BGP and on-path attackers can subvert the routing assumption, and because it provides none of the cryptographic guarantees (confidentiality, integrity, replay protection, non-repudiation) that a real authentication scheme requires.

In your Freshdesk case specifically: whitelisting Netlify/AWS egress means whitelisting a large multi-tenant pool, which any attacker can join for free. The only durable fix is to **authenticate the request itself** — short-lived JWT from your app to the proxy, Freshdesk API key held server-side, TLS end-to-end, and optional HMAC/timestamp for integrity and replay protection — and treat the source IP as a hint, never as a credential.

## The Solution


A more robust approach to security has been discussed below:

We'll take **Freshdesk API with a WAF** as an example.

To get Freshdesk's WAF to consistently allow your requests, you need to move beyond static secrets and design a system where the "special header" is **cryptographically bound to each request**. A static header value, even if kept secret, can be replayed or leaked. The solution is a **signed request header** generated on the server, using a secret that never leaves Netlify.

This approach provides a durable bypass because the WAF rule can be configured to look for a valid, unique signature rather than a guessable string.

### 🛡️ The Core Mechanism: HMAC Request Signing

Instead of sending a fixed token, your Netlify Function will compute a **Hash-based Message Authentication Code (HMAC)** for every outgoing request to Freshdesk. This signature proves the request was generated by someone holding the secret key and that the request hasn't been tampered with in transit.

The WAF is then configured to validate this signature. Because the signature changes for every request (incorporating a timestamp, a unique nonce, and the request body), an attacker who intercepts one request cannot reuse the header for a different request or replay the same request later.

### ⚙️ Real-World Implementation on Netlify

Here is how to implement this securely on Netlify, addressing the platform's constraints.

#### 1. Store the Secret Key Securely
Use **Netlify's Secrets Controller** to store your HMAC secret key. This goes beyond standard environment variables by enforcing a write-only policy, meaning the value cannot be read back from the UI or API after it is set, and restricting it to only be accessible by your serverless functions at runtime.

```bash
# Store the secret using the Netlify CLI
netlify env:set HMAC_SECRET "your-super-long-random-string" --secret
```

#### 2. Generate the Signature in a Netlify Function
Your Netlify Function acts as the proxy. It constructs a canonical string from the request, signs it with the secret, and attaches the signature and related metadata as headers.

```javascript
const crypto = require('crypto');

exports.handler = async (event) => {
  // ... (Your existing JWT verification logic for client auth)

  const freshdeskUrl = `https://${process.env.FRESHDESK_DOMAIN}${event.path}`;
  const timestamp = Date.now().toString();
  const nonce = crypto.randomBytes(16).toString('hex');
  const body = event.body || '';

  // Create the canonical string to sign (order matters and must match the WAF validator)
  const canonicalString = `${event.httpMethod}\n${event.path}\n${timestamp}\n${nonce}\n${body}`;
  
  // Generate the HMAC signature using the secret from Netlify Secrets Controller
  const signature = crypto
    .createHmac('sha256', process.env.HMAC_SECRET)
    .update(canonicalString)
    .digest('hex');

  const headers = {
    'Content-Type': 'application/json',
    'Authorization': `Basic ${Buffer.from(`${process.env.FRESHDESK_API_KEY}:X`).toString('base64')}`,
    'X-Signature': signature,      // The dynamic, cryptographic header
    'X-Timestamp': timestamp,      // Prevents replay attacks
    'X-Nonce': nonce,              // Adds uniqueness to every request
  };

  const response = await fetch(freshdeskUrl, {
    method: event.httpMethod,
    headers: headers,
    body: event.httpMethod === 'GET' ? undefined : body,
  });

  // ... (Return response to client)
};
```

#### 3. What the Freshdesk WAF Must Validate
You would need to coordinate with Freshdesk support to configure a WAF rule that performs the following on requests to your specific API key or domain:

1.  **Check for Presence:** Verify that the `X-Signature`, `X-Timestamp`, and `X-Nonce` headers exist.
2.  **Prevent Replay:** Reject the request if the `X-Timestamp` is too old (e.g., older than 5 minutes) or if the `X-Nonce` has been seen before.
3.  **Recompute and Compare:** Rebuild the canonical string using the incoming method, path, timestamp, nonce, and body, then compute the HMAC using the pre-shared secret. If the computed signature does not match the `X-Signature` header, block the request.

### ⚠️ Critical Constraint: The Egress IP Problem

This cryptographic header solves the *authentication* problem, but it does **not** solve the *network path* problem. Netlify Functions run on AWS Lambda with **dynamic, rotating egress IPs**; Netlify does not provide a static outbound IP on standard plans.

If Freshdesk's WAF is blocking entire AWS or Cloudflare IP ranges based on reputation, your signed request may still be blocked before the WAF even inspects the headers. A cryptographic signature cannot force an IP-based block to be lifted.

**The practical path forward is twofold:**

1.  **Engage Freshdesk Support:** Present this signed-header design. Ask if their WAF can be configured to allowlist requests that carry a valid HMAC signature for your API key, regardless of the source IP. This is the only way to achieve a true header-based bypass.
2.  **Have a Network Fallback Ready:** If Freshdesk confirms the block is purely IP-based and cannot be bypassed via headers, you will need a static egress IP. Since you want to avoid a VM, the serverless options are **Netlify's Private Connectivity** (an Enterprise add-on) or a lightweight **static IP proxy service** like QuotaGuard or Fixie, which provides a fixed IP endpoint for your function's outbound traffic.

### 💎 Summary of Protection Layers

| Layer | Mechanism | Purpose |
| :--- | :--- | :--- |
| **Secret Storage** | Netlify Secrets Controller | Protects the HMAC key from exposure in logs, UI, or code. |
| **Header Authenticity** | HMAC-SHA256 Signature | Proves the request was generated by your authorized code and was not tampered with. |
| **Replay Prevention** | `X-Timestamp` & `X-Nonce` | Ensures an intercepted request cannot be reused later. |
| **Client Auth** | Short-lived JWT (from your app) | Ensures only your authorized frontend can invoke the signing function. |

This design makes the header computationally infeasible to forge or guess. The remaining variable is whether Freshdesk's WAF can be configured to validate it instead of relying on source IP.

If this solution is not feasible because the third-party service (E.g. Freshdesk) rejects your approach to allow your specific header to life the block and still insist they block on a IP-address block basis then scroll down to the alternate solution discussed later in this article.

### A note about attackers who can spoof IP addresses: Can they actually be successful and how successful can they be?

Short answer: **No, an off-path attacker cannot just set their source IP to your whitelisted IP and complete a TCP/TLS session with Freshdesk.** But **IP whitelisting is not authentication** — it can be bypassed in specific scenarios, so you should never rely on it alone.

#### Why simple IP spoofing usually fails

Freshdesk’s WAF looks at the **TCP source IP** of the connection. To “spoof” your whitelisted IP, an attacker would have to:

1. Send packets with your whitelisted IP as the source.
2. Receive Freshdesk’s replies — because TCP requires a 3-way handshake.
3. Complete the TLS handshake and then authenticate with the Freshdesk API key.

If the attacker is **not on the network path** between your proxy and Freshdesk, the replies go to your real whitelisted IP, not to them. They never see the SYN-ACK, so they cannot complete the handshake. Blind TCP spoofing requires guessing sequence numbers, which is impractical against modern stacks, and TLS makes it even harder.

So from a random internet location: **spoofing the whitelisted IP alone will not work.**

### When it *is* possible

IP whitelisting can be bypassed if:

- **The attacker is on-path (a true MITM).** If they sit between your proxy and Freshdesk, they can intercept return traffic and potentially inject packets with your source IP. But they still need to break TLS or steal your Freshdesk API key to do anything useful.
- **They compromise a host that legitimately uses that IP.** For example, if they compromise your AWS NAT Gateway, a Netlify Function egress host, or any proxy in that IP range, they appear from the whitelisted IP naturally.
- **They use an open proxy or SSRF in a service hosted in that IP range.**
- **BGP hijacking / routing compromise.** At a nation-state or large ISP level, an attacker could attract traffic for that IP prefix. This is rare but possible.
- **The WAF trusts a spoofable header** like `X-Forwarded-For`. If Freshdesk incorrectly trusts client-supplied forwarding headers, then yes, an attacker could spoof the IP in a header. Most reputable WAFs use the actual TCP source IP, but it’s worth confirming.

### What this means for your design

Knowing the whitelisted IP is not a secret — IPs are public routing information. Your security must not depend on the IP being unknown or unspoofable.

That’s why the earlier design uses:

- **TLS with certificate validation** — prevents passive snooping and active MITM unless the attacker can forge a trusted certificate.
- **Short-lived JWT from your app → Netlify proxy** — authenticates the client without exposing secrets.
- **HMAC signature + timestamp** — proves integrity and origin for your own audit/WAF identification, and prevents replay if you validate it.
- **Freshdesk API key stored only server-side** — never exposed to the browser.
- **Optional certificate pinning** in your proxy for Freshdesk’s TLS certificate — makes MITM with a rogue CA much harder.
- **Secret rotation and monitoring** — limits damage if a key is ever leaked.

### Important caveat about Freshdesk

Freshdesk does **not** natively verify your custom HMAC header. Its API authentication is typically **HTTP Basic Auth with an API key over TLS**. So on the proxy → Freshdesk leg, the real cryptographic protections are:

1. TLS (confidentiality + integrity).
2. Freshdesk API key (authorization).

The HMAC/JWT headers mainly protect the **client → your proxy** leg and help with WAF identification. If you want cryptographic authentication all the way to Freshdesk, you’d need Freshdesk to support mTLS or request signing — check their enterprise/API docs. If they don’t, the best you can do is protect the API key and use TLS correctly.

### Practical bottom line

- **Off-path attacker spoofing your whitelisted IP:** practically not feasible for a full TCP/TLS session.
- **On-path attacker or compromised whitelisted host:** yes, they can appear from that IP, but they still need the Freshdesk API key or a valid JWT/HMAC secret.
- **Therefore:** keep IP whitelisting only as an extra layer. Make your real authentication cryptographic — JWT for your app, server-side API key for Freshdesk, TLS everywhere, short expirations, and replay protection.

If Freshdesk’s WAF still blocks Netlify’s egress IPs, you may eventually need a static egress IP from a serverless service like AWS Lambda + NAT Gateway (not a VM). But even then, keep the JWT/HMAC and API-key controls so that knowing or spoofing the IP doesn’t grant access.



Debate on not using a static public IP solution:

You’re right to push back on the AWS/Azure public-IP proxy. It adds cost, latency, another hop, and a stateful component you have to operate. IP whitelisting is a blunt instrument and should not be your primary security control.

But there’s an important distinction to make before designing this:

## WAF blocking ≠ API authentication

Freshdesk’s WAF blocks at the edge **before** it evaluates your Freshdesk API key, HMAC header, or JWT. A WAF generally looks at:

- source IP reputation
- TLS fingerprint
- request rate
- headers / User-Agent
- payload heuristics
- bot signals

It does **not** know your custom `X-Freshdesk-Signature` or `Authorization: Bearer <JWT>` unless Freshdesk has explicitly configured the WAF to trust that header. Most WAFs do not.

So you cannot cryptographically force a third-party WAF to stop blocking you. You can only:

1. **Change the egress path** so Freshdesk sees an IP/network it doesn’t block, or
2. **Get Freshdesk to allowlist your account/API key/IP** in their WAF, or
3. **Fix the request pattern** if the block is not IP-based.

That’s the hard constraint.

## An alternate solution - sending your outbound traffic from Netlify through a Cloudflare worker



### Serverless edge proxy (Cloudflare Workers, Deno Deploy, etc.)

If Netlify Edge Functions are still blocked, use a small serverless proxy on a network Freshdesk doesn’t block. Cloudflare Workers are a good fit:

- no VM
- no public IP to whitelist
- free/cheap tier
- runs at the edge
- holds Freshdesk API key server-side
- verifies a JWT from your app
- adds one hop, but minimal

This is not the AWS/Azure public-IP VM solution you rejected. It’s a serverless function, similar to what you already have in Netlify, just on a different egress network.

## Cryptographic design that avoids MITM and snooping

Regardless of which proxy you use, the security model is:

```
[Browser / Netlify App]
   │  HTTPS + short-lived JWT
   ▼
[Proxy: Netlify Edge Function or Cloudflare Worker]
   │  HTTPS + Freshdesk API key + optional HMAC
   ▼
[Freshdesk API]
```

### Factor 1 — Short-lived JWT from your app to the proxy

- Your app requests a JWT from an auth endpoint you control.
- JWT is signed with RS256/ES256.
- Expiry: 1–5 minutes.
- Audience: your proxy.
- Scope: e.g., `freshdesk:ticket:create`.
- Include `jti` (nonce) to prevent replay.
- Proxy verifies signature, expiry, audience, scope.

This proves the request came from your authorized app, not a random client.

### Factor 2 — Freshdesk API key stored only server-side

- The proxy holds `FRESHDESK_API_KEY` in environment variables.
- It sends it to Freshdesk using HTTP Basic Auth over TLS.
- The browser never sees the API key.

This is the second factor: something the server knows.

### Optional integrity layer — HMAC signature

- Proxy computes `HMAC-SHA256(method + path + timestamp + body, HMAC_SECRET)`.
- Sends it as `X-Freshdesk-Signature` with `X-Freshdesk-Timestamp`.
- Freshdesk may not validate it, but you can log it and show it to Freshdesk support as proof of legitimate origin.
- If you ever build your own middleware, you can validate it to prevent tampering and replay.

### TLS

- All traffic is HTTPS/TLS 1.2+.
- Your proxy validates Freshdesk’s TLS certificate.
- If possible, pin Freshdesk’s CA in your proxy.
- This prevents passive snooping and most active MITM.

## Can a MITM spoof the whitelisted IP?

Not practically, if they are off-path:

- TCP requires a 3-way handshake.
- TLS requires a valid certificate.
- If they spoof your source IP, Freshdesk’s replies go to your real IP, not to them.
- They cannot complete the handshake or decrypt TLS without the certificate/keys.

If they are on-path or compromise a host that legitimately uses that IP, they can appear from it. But they still need the Freshdesk API key or a valid JWT to do anything useful. That’s why the crypto layer matters more than the IP.

## Bottom line

You cannot force Freshdesk’s WAF to stop blocking you with custom headers or crypto alone. The WAF is a separate control plane.

To avoid AWS/Azure public-IP whitelisting:

1. **First**, try Netlify Edge Functions instead of Netlify Functions — different egress, no new service.
2. **If that fails**, use a serverless edge proxy like Cloudflare Workers — no VM, no static IP, cheap, serverless.
3. **In parallel**, open a Freshdesk support ticket and ask them to allowlist your API key/account or adjust the WAF rule.
4. **Always** keep the cryptographic design: short-lived JWT from app → proxy, Freshdesk API key server-side, TLS everywhere, optional HMAC + timestamp for integrity and audit.

That gives you strong service-to-service authentication without relying on IP whitelisting as your security boundary.


Cloudflare solution:

Here is a detailed elaboration on using Cloudflare Workers as a serverless edge proxy for your Freshdesk integration.

---

## Architecture: Cloudflare Worker as Secure Proxy

```
[Browser / Netlify App]
       │  HTTPS + Short-lived JWT (Factor 1)
       ▼
[Cloudflare Worker (Edge Proxy)]
       │  - Verifies JWT signature, expiry, audience
       │  - Holds Freshdesk API key server-side (Factor 2)
       │  - Adds HMAC signature + timestamp
       │  HTTPS + Basic Auth (API key:X) + custom headers
       ▼
[Freshdesk API]
       WAF sees Cloudflare egress IPs (different network from Netlify/AWS)
```

**Why this works for the WAF block:** Netlify Functions run on AWS Lambda, whose egress IPs Freshdesk is apparently blocking. Cloudflare Workers run on Cloudflare's global edge network, so requests to Freshdesk originate from Cloudflare's egress IP ranges — a completely different network path. This is not a static IP you manage; it's Cloudflare's shared egress pool, which Freshdesk's WAF generally does not block.

---

## Step 1: Set Up the Worker Project

Install Wrangler CLI and initialize a project:

```bash
npm install -g wrangler
wrangler login
mkdir freshdesk-proxy-worker && cd freshdesk-proxy-worker
npm init -y
```

Create `wrangler.toml`:

```toml
name = "freshdesk-proxy"
main = "src/index.js"
compatibility_date = "2026-09-16"
```

---

## Step 2: Store Secrets Securely

Use Cloudflare Workers Secrets — encrypted values not visible in the dashboard or Wrangler config after creation:

```bash
wrangler secret put FRESHDESK_API_KEY
# Paste your Freshdesk API key (e.g., fdp_xxxxxxxx)

wrangler secret put FRESHDESK_DOMAIN
# Paste your subdomain (e.g., yourcompany.freshdesk.com)

wrangler secret put JWT_SECRET
# Paste a long random string used to verify client JWTs

wrangler secret put HMAC_SECRET
# Paste a long random string for HMAC signing
```

For local development, create a `.dev.vars` file with the same keys and placeholder values. Cloudflare Workers secrets are accessed through the `env` parameter in your fetch handler or via `import { env } from "cloudflare:workers"`.

---

## Step 3: Implement the Worker Code

Here is the complete Worker implementation. Save as `src/index.js`:

```javascript
// src/index.js

// --- JWT verification (HMAC-SHA256) using Web Crypto ---
async function verifyJWT(token, secret) {
  const parts = token.split('.');
  if (parts.length !== 3) return null;

  const [headerB64, payloadB64, signatureB64] = parts;

  // Verify signature
  const key = await crypto.subtle.importKey(
    'raw',
    new TextEncoder().encode(secret),
    { name: 'HMAC', hash: 'SHA-256' },
    false,
    ['verify']
  );

  const valid = await crypto.subtle.verify(
    'HMAC',
    key,
    base64UrlToUint8Array(signatureB64),
    new TextEncoder().encode(`${headerB64}.${payloadB64}`)
  );
  if (!valid) return null;

  // Decode payload and check expiry / audience
  const payload = JSON.parse(atob(payloadB64.replace(/-/g, '+').replace(/_/g, '/')));
  if (payload.exp && Date.now() / 1000 > payload.exp) return null;
  if (payload.aud !== 'freshdesk-proxy') return null;

  return payload;
}

function base64UrlToUint8Array(base64url) {
  const base64 = base64url.replace(/-/g, '+').replace(/_/g, '/');
  const pad = base64.length % 4;
  const padded = pad ? base64 + '='.repeat(4 - pad) : base64;
  const binary = atob(padded);
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i++) bytes[i] = binary.charCodeAt(i);
  return bytes;
}

// --- HMAC signing for Freshdesk request integrity ---
async function signRequest(method, path, timestamp, body, secret) {
  const payload = `${method}\n${path}\n${timestamp}\n${body || ''}`;
  const key = await crypto.subtle.importKey(
    'raw',
    new TextEncoder().encode(secret),
    { name: 'HMAC', hash: 'SHA-256' },
    false,
    ['sign']
  );
  const sig = await crypto.subtle.sign('HMAC', key, new TextEncoder().encode(payload));
  return [...new Uint8Array(sig)].map(b => b.toString(16).padStart(2, '0')).join('');
}

// --- Main Worker handler ---
export default {
  async fetch(request, env) {
    // Only allow POST and GET
    if (!['POST', 'GET'].includes(request.method)) {
      return new Response('Method not allowed', { status: 405 });
    }

    // --- Factor 1: Verify short-lived JWT from the client ---
    const authHeader = request.headers.get('Authorization') || '';
    const token = authHeader.startsWith('Bearer ') ? authHeader.slice(7) : null;
    if (!token) {
      return new Response('Missing authorization token', { status: 401 });
    }

    const jwtPayload = await verifyJWT(token, env.JWT_SECRET);
    if (!jwtPayload) {
      return new Response('Invalid or expired token', { status: 401 });
    }

    // Optional: check scope from JWT payload
    if (!jwtPayload.scope?.includes('freshdesk:ticket:create')) {
      return new Response('Insufficient scope', { status: 403 });
    }

    // --- Build the Freshdesk request ---
    const url = new URL(request.url);
    const freshdeskPath = url.pathname; // e.g., /api/v2/tickets
    const freshdeskUrl = `https://${env.FRESHDESK_DOMAIN}${freshdeskPath}${url.search}`;

    const body = request.method === 'POST' ? await request.text() : undefined;
    const timestamp = Date.now().toString();

    // --- Factor 2: Freshdesk API key (HTTP Basic Auth) ---
    // Freshdesk uses the API key as username and "X" as password
    const authBasic = btoa(`${env.FRESHDESK_API_KEY}:X`);

    // Optional HMAC signature for audit / integrity
    const hmacSignature = await signRequest(
      request.method,
      freshdeskPath,
      timestamp,
      body,
      env.HMAC_SECRET
    );

    // --- Forward to Freshdesk ---
    const freshdeskResponse = await fetch(freshdeskUrl, {
      method: request.method,
      headers: {
        'Authorization': `Basic ${authBasic}`,
        'Content-Type': request.headers.get('Content-Type') || 'application/json',
        'User-Agent': 'MyNetlifyApp-WorkerProxy/1.0',
        'X-Proxy-Timestamp': timestamp,
        'X-Proxy-Signature': hmacSignature,
      },
      body: body,
    });

    // --- Return response to client ---
    const responseBody = await freshdeskResponse.text();
    return new Response(responseBody, {
      status: freshdeskResponse.status,
      headers: {
        'Content-Type': freshdeskResponse.headers.get('Content-Type') || 'application/json',
        'Access-Control-Allow-Origin': '*', // Adjust to your Netlify domain in production
      },
    });
  },
};
```

**Key points in the code:**

- The JWT is verified entirely in-Worker using Web Crypto (no external dependencies).
- Freshdesk API key is never exposed to the client — it lives only in Workers Secrets.
- The `X-Proxy-Signature` and `X-Proxy-Timestamp` headers travel to Freshdesk. Freshdesk's WAF will not validate them, but you can log them and present them to Freshdesk support as evidence of legitimate requests.
- CORS headers allow your Netlify app to call the Worker. Replace `*` with your Netlify domain in production.

---

## Step 4: Generate JWTs from Your App

Your Netlify app (or a Netlify Function) must issue short-lived JWTs before calling the Worker. Here is a minimal Netlify Function example using `jsonwebtoken`:

```javascript
// netlify/functions/auth.js
const jwt = require('jsonwebtoken');

exports.handler = async (event) => {
  // Authenticate the user however you normally do (session, OAuth, etc.)
  // Then issue a short-lived JWT scoped to the Freshdesk proxy:
  const token = jwt.sign(
    {
      sub: 'user-123',
      aud: 'freshdesk-proxy',
      scope: ['freshdesk:ticket:create'],
    },
    process.env.JWT_SECRET, // Same secret as in the Worker
    { expiresIn: '5m', algorithm: 'HS256' }
  );

  return {
    statusCode: 200,
    body: JSON.stringify({ token }),
  };
};
```

Your frontend then:
1. Calls `/.netlify/functions/auth` to get a JWT.
2. Calls the Cloudflare Worker with `Authorization: Bearer <token>`.

---

## Step 5: Egress IP Behavior (Critical for WAF)

This is the most important detail for your specific problem.

**Cloudflare Workers do not use a static egress IP on the free or standard paid plans.** Requests from Workers to external APIs originate from Cloudflare's shared edge egress pool — the same ranges published for Cloudflare's CDN infrastructure. You **cannot** whitelist a single IP at Freshdesk for this.

However, this is actually **good** for your use case:
- Freshdesk's WAF is blocking AWS Lambda / Netlify egress ranges.
- Cloudflare's egress ranges are a different network entirely.
- Freshdesk likely does **not** block Cloudflare's ranges because Cloudflare is a major CDN provider and blocking it would break many legitimate integrations.

**If Freshdesk still blocks Cloudflare ranges**, you have two options:

1. **Cloudflare Enterprise Egress Policies** — Cloudflare offers dedicated egress IPs on enterprise plans. This gives you a stable IP you can whitelist at Freshdesk. It adds cost, but it is a serverless feature, not a VM.

2. **Cloudflare Tunnel with a static IP** — You can run a lightweight `cloudflared` connector on any host with a static IP (even a tiny $5 VPS). The Worker sends traffic through the tunnel, and Freshdesk sees the static IP of the tunnel endpoint. This is still lighter than a full proxy VM because the Worker handles all logic; the tunnel is just a network path.

---

## Security Analysis

### MITM and snooping resistance

| Layer | Protection |
|---|---|
| **Client → Worker** | HTTPS + short-lived JWT (HS256). Token expires in 5 minutes; replay is impractical. |
| **Worker → Freshdesk** | HTTPS with TLS certificate validation by the Workers runtime. Freshdesk's certificate is validated automatically. |
| **API key** | Stored in Workers Secrets, never exposed to the client or in logs. |
| **HMAC signature** | Provides integrity for the request payload; can be validated if you ever build custom middleware. |
| **Timestamp** | Prevents replay if you later add server-side validation. |

**Can a MITM spoof the Worker's egress IP?** No, for the same reasons discussed earlier: TCP handshake and TLS make blind spoofing impractical. And because the Worker uses Cloudflare's shared egress, there is no single IP to target.

### What the Worker does *not* solve

The Worker does **not** make Freshdesk's WAF validate your JWT or HMAC. The WAF will still evaluate the request based on source IP, rate, headers, and payload. The Worker solves the problem by **changing the source network**, not by cryptographically forcing the WAF to accept you.

---

## Cost and Comparison

| Aspect | Cloudflare Worker | AWS/Azure VM Proxy |
|---|---|---|
| **Cost** | Free tier: 100k requests/day. Paid: $5/month for 10M requests. | $10–$30+/month for a small VM, plus data transfer. |
| **Cold start** | None (V8 isolates, sub-millisecond). | VM is always running (or Lambda cold starts). |
| **Egress IP** | Shared Cloudflare ranges (different from AWS). | Static IP you can whitelist. |
| **Maintenance** | Zero servers, zero patching. | OS updates, security patches, monitoring. |
| **Global latency** | Runs at the edge near the user. | Single region. |
| **Secrets** | Built-in encrypted secrets. | Manual (env vars, vault). |

The Worker is cheaper, has no cold starts, requires no server maintenance, and changes the egress network — which is exactly what you need to escape the WAF block.

---

## Limitations and Troubleshooting

1. **Worker egress IPs are shared.** If Freshdesk blocks Cloudflare ranges (unlikely but possible), you need Enterprise Egress Policies or a Cloudflare Tunnel with a static endpoint.

2. **No request body streaming for large payloads.** Workers have memory limits (128 MB on free tier). Freshdesk API payloads are small, so this is not a concern.

3. **JWT secret rotation.** If you rotate the JWT secret, you must update it in both the Netlify auth function and the Worker secret simultaneously. Plan for zero-downtime rotation by supporting two valid secrets during a transition window.

4. **CORS.** The Worker must return the correct `Access-Control-Allow-Origin` header. Set it to your Netlify domain, not `*`, in production.

5. **Freshdesk rate limits.** The Worker does not add rate limiting by default. If needed, use Workers KV or Durable Objects to implement per-user rate limits before forwarding to Freshdesk.

---

## Summary

Using a Cloudflare Worker as your Freshdesk proxy gives you:

- **A different egress network** (Cloudflare edge, not AWS Lambda) — solves the WAF block without a VM.
- **Two-factor service authentication** — short-lived JWT from your app + Freshdesk API key stored server-side.
- **Cryptographic integrity** — HMAC signing and TLS end-to-end.
- **Zero server management** — serverless, edge-deployed, cheap.
- **No static IP to manage** — unless Freshdesk blocks Cloudflare ranges, in which case Enterprise Egress Policies or a Cloudflare Tunnel provide a static endpoint without a full VM.

This is the lightest architectural change that addresses both the WAF block and the security requirements, without introducing the cost, latency, or operational burden of an AWS/Azure public-IP proxy.

## Author - Pranesh Sathyanarayan
### Published First : 21 Oct 2026
### AI agent disclosure - Deep Seek AI was used to generate content

#### "This work is dedicated to the public domain under CC0 1.0 Universal. You are free to copy, modify, distribute, and perform the work, even for commercial purposes, all without asking permission."
