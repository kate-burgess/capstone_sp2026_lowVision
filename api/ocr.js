// Proxies Flutter web requests to the OCR/VLM Flask server (HTTPS page -> HTTP backend).
// Set Vercel env: OCR_PROXY_TARGET (e.g. http://128.180.121.230:5010)
//
// Uses the Web Request/Response handler so the body is read via standard APIs (reliable on
// Vercel). The Next.js-only `export const config = { api: { bodyParser: false } }` does not
// apply to this Flutter static deployment; if you ever need raw IncomingMessage without
// helpers, set env NODEJS_HELPERS=0 per Vercel docs.

export default {
  async fetch(request) {
    let targetUrlString = "";
    try {
      const targetBase = (process.env.OCR_PROXY_TARGET || "").replace(/\/$/, "");
      if (!targetBase) {
        return Response.json(
          {
            error:
              "OCR_PROXY_TARGET is not set. Set it in Vercel Environment Variables (e.g. http://128.180.121.230:5010).",
          },
          { status: 500 },
        );
      }

      const incoming = new URL(request.url);
      let path = incoming.searchParams.get("path") || "/extract-text";
      if (!path.startsWith("/")) path = `/${path}`;

      const targetUrl = new URL(path, `${targetBase}/`);
      targetUrlString = targetUrl.toString();

      const method = request.method;
      const forwardHeaders = {};
      const ct = request.headers.get("content-type");
      if (ct) forwardHeaders["content-type"] = ct;

      let body;
      if (method !== "GET" && method !== "HEAD") {
        const buf = await request.arrayBuffer();
        body = buf.byteLength > 0 ? buf : undefined;
      }

      const upstream = await fetch(targetUrlString, {
        method,
        headers: forwardHeaders,
        body,
        // Flask on a single host: no redirect follow required; keeps errors visible.
      });

      const outBuf = await upstream.arrayBuffer();
      const outHeaders = new Headers();
      const uct = upstream.headers.get("content-type");
      if (uct) outHeaders.set("content-type", uct);

      return new Response(outBuf, { status: upstream.status, headers: outHeaders });
    } catch (err) {
      return Response.json(
        {
          error: "Proxy request failed",
          detail: String(err),
          target: targetUrlString || undefined,
        },
        { status: 502 },
      );
    }
  },
};
