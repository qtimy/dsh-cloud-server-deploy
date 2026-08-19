#!/usr/bin/env bash
# patch-realtime.sh — idempotent re-apply of the DSH realtime-connectivity patches.
#
# Problem it fixes: the web GUI pushes session events over server-to-browser
# streams (/api/events.mux, /api/events.host — WebSocket in the browser, SSE for
# in-process clients). Idle streams emitted zero bytes, so NATs/proxies/browser
# sleep silently reaped the socket (half-open TCP). The client only reconnects
# when the stream errors or ends, so a silently dead connection left the page
# stale until a manual refresh.
#
# Patches:
#   1. server dsh-host-apiproxy .../fetch/handler.js (SSE path): periodic
#      `: keepalive` comment every 15s on every SSE stream.
#   2. server dsh-client-connection/lib/index.js (WebSocket path): periodic
#      `stream/heartbeat` frame every 15s per open downlink socket.
#   3. client dsh-client-connection/lib/client.js:
#        - accept `stream/heartbeat` frames in the mux/host frame schemas;
#        - wire-liveness watchdog (abort + reconnect after 45s of silence);
#        - visibilitychange handler forcing a fresh reconnect on tab return;
#        - wire-activity tracking in both the SSE reader and WebSocket reader.
#
# Every sub-edit is idempotent (skipped when its new content is already present)
# and loud when an anchor is missing (upstream refactor). Exits 0 when everything
# is in place, 1 with warnings otherwise. Implemented in python3 for reliable
# multi-line string handling.
set -uo pipefail

python3 - <<'PY'
import sys

FILES = {
    "handler": "/usr/lib/node_modules/@deepseek-ai/dsh/node_modules/@deepseek-ai/dsh-host-apiproxy/lib/types/fetch/handler.js",
    "downlink": "/usr/lib/node_modules/@deepseek-ai/dsh/node_modules/@deepseek-ai/dsh-client-connection/lib/index.js",
    "client": "/usr/lib/node_modules/@deepseek-ai/dsh/node_modules/@deepseek-ai/dsh-client-connection/lib/client.js",
}

# (file_key, old, new, marker, label)
EDITS = [
    # ---- 1. server SSE heartbeat (handler.js) ----
    ("handler",
"""    const stream = new ReadableStream({
        async start(controller) {
            try {
                // Send an SSE comment line on open so clients/proxies see a live channel (the host
                // stream has no baseline frames and would otherwise emit zero bytes while idle;
                // a comment line is not a frame, so client frame parsing skips it naturally).
                controller.enqueue(encoder.encode(': connected\\n\\n'));
                for await (const narrow of frames) {
                    controller.enqueue(encoder.encode(`data: ${JSON.stringify(fullFrame(narrow))}\\n\\n`));
                }
            }""",
"""    const stream = new ReadableStream({
        async start(controller) {
            // Periodic SSE comment heartbeat while the upstream stays open. Idle streams would
            // otherwise emit zero bytes, so NATs/proxies/browsers silently reap the socket
            // (half-open TCP) and the client hangs on a dead stream with no error — stale UI
            // until a manual refresh. The comment keeps the channel alive through idle
            // timeouts and gives the client watchdog a liveness signal; it is not a frame,
            // so client frame parsing skips it naturally.
            const heartbeat = setInterval(() => {
                try {
                    controller.enqueue(encoder.encode(': keepalive\\n\\n'));
                }
                catch {
                    clearInterval(heartbeat);
                }
            }, 15_000);
            try {
                // Send an SSE comment line on open so clients/proxies see a live channel (the host
                // stream has no baseline frames and would otherwise emit zero bytes while idle;
                // a comment line is not a frame, so client frame parsing skips it naturally).
                controller.enqueue(encoder.encode(': connected\\n\\n'));
                for await (const narrow of frames) {
                    controller.enqueue(encoder.encode(`data: ${JSON.stringify(fullFrame(narrow))}\\n\\n`));
                }
            }""",
": keepalive\\n\\n",
"server SSE heartbeat"),
    ("handler",
"""            finally {
                try {
                    controller.close();
                }
                catch { /* already cancelled by the consumer: a double close is the only reachable error */ }
            }""",
"""            finally {
                clearInterval(heartbeat);
                try {
                    controller.close();
                }
                catch { /* already cancelled by the consumer: a double close is the only reachable error */ }
            }""",
"finally {\n                clearInterval(heartbeat);",
"server SSE heartbeat cleanup"),
    # ---- 2. server WebSocket heartbeat (downlink index.js) ----
    ("downlink",
"""	async pump(socket, frames, abort) {
		try {
			for await (const frame of frames) await send(socket, frame);
		} catch (error) {
			if (!abort.signal.aborted) try {
				await send(socket, failureFrame(error));
			} catch {}
		} finally {
			abort.abort();
			if (socket.readyState === WebSocket.OPEN) socket.close();
		}
	}""",
"""	async pump(socket, frames, abort) {
		// Application-level heartbeat frame while the socket stays open. Idle streams
		// would otherwise emit zero bytes, so NATs/proxies/browser sleep silently reap
		// the socket (half-open TCP) and the client hangs on a dead channel with no
		// error — stale UI until a manual refresh. The client treats the frame as a
		// liveness signal and ignores it otherwise.
		const heartbeat = setInterval(() => {
			if (socket.readyState !== WebSocket.OPEN) return;
			send(socket, {
				rpcId: RpcId(randomUUID()),
				payload: { type: "stream/heartbeat" }
			}).catch(() => {});
		}, 15_000);
		try {
			for await (const frame of frames) await send(socket, frame);
		} catch (error) {
			if (!abort.signal.aborted) try {
				await send(socket, failureFrame(error));
			} catch {}
		} finally {
			clearInterval(heartbeat);
			abort.abort();
			if (socket.readyState === WebSocket.OPEN) socket.close();
		}
	}""",
'payload: { type: "stream/heartbeat" }',
"server WebSocket heartbeat"),
    # ---- 3a. client liveness constants ----
    ("client",
"""		const CONNECTION_DEFAULTS = {
			backoffBaseMs: 500,
			backoffFactor: 2,
			backoffMaxMs: 1e4,
			streamOpenTimeoutMs: 3e3
		};""",
"""		const CONNECTION_DEFAULTS = {
			backoffBaseMs: 500,
			backoffFactor: 2,
			backoffMaxMs: 1e4,
			streamOpenTimeoutMs: 3e3
		};
		/** Wire-liveness bookkeeping shared by the SSE readers and the reconnect watchdog.
		* Keyed by the generation's AbortSignal; every byte chunk (SSE comment heartbeats
		* included) refreshes the timestamp. The server heartbeats every 15s, so silence
		* well beyond that means the socket died silently (half-open TCP) and the read
		* would otherwise hang forever with no error. */
		const wireActivity = /* @__PURE__ */ new Map();
		const WATCHDOG_POLL_MS = 15e3;
		const WATCHDOG_IDLE_MS = 45e3;""",
"const WATCHDOG_IDLE_MS = 45e3;",
"client liveness constants"),
    # ---- 3b. client visibility reconnect ----
    ("client",
"""			/** Idempotent: begin the connect/pump/reconnect loop. */
			start() {
				if (this.running) return;
				this.running = true;
				this.loop();
			}
			/** Stop the loop and abort the current generation's streams. */
			stop() {
				this.running = false;
				this.current?.abort();
				this.current = null;
			}""",
"""			/** Idempotent: begin the connect/pump/reconnect loop. */
			start() {
				if (this.running) return;
				this.running = true;
				/* Returning to a backgrounded/slept tab: the previous generation's sockets are
				* almost certainly dead (browsers throttle timers while hidden, OS sleep kills
				* every TCP connection) and neither side notices until data flows again. Force a
				* fresh generation on visibility so the UI re-syncs immediately instead of
				* waiting for the watchdog. */
				this.onVisibilityChange = () => {
					if (typeof document === "undefined") return;
					if (document.visibilityState !== "visible") return;
					if (!this.isRunning()) return;
					this.attempt = 0;
					this.current?.abort();
				};
				if (typeof document !== "undefined") document.addEventListener("visibilitychange", this.onVisibilityChange);
				this.loop();
			}
			/** Stop the loop and abort the current generation's streams. */
			stop() {
				this.running = false;
				if (typeof document !== "undefined" && this.onVisibilityChange !== void 0) document.removeEventListener("visibilitychange", this.onVisibilityChange);
				this.current?.abort();
				this.current = null;
			}""",
"this.onVisibilityChange = () => {",
"client visibility reconnect"),
    # ---- 3c. client reconnect watchdog ----
    ("client",
"""				while (this.running) {
					const gen = ++this.generation;
					const ac = new AbortController();
					this.current = ac;
					/* v8 ignore next -- initializer placeholder: the Promise executor""",
"""				while (this.running) {
					const gen = ++this.generation;
					const ac = new AbortController();
					this.current = ac;
					/* Reconnect watchdog: abort the generation when the wire shows no bytes for
					* WATCHDOG_IDLE_MS. The server heartbeats every 15s, so silence that long means
					* the socket is silently dead (half-open TCP) — a read that never errors.
					* Aborting ends the pumps below, which settles `failed` and reconnects. */
					const watchdog = setInterval(() => {
						if (!this.isRunning() || gen !== this.generation) return;
						const last = wireActivity.get(ac.signal);
						if (last === void 0) return;
						if (Date.now() - last <= WATCHDOG_IDLE_MS) return;
						console.warn("[web-runtime] stream idle watchdog fired; forcing reconnect");
						ac.abort();
					}, WATCHDOG_POLL_MS);
					/* v8 ignore next -- initializer placeholder: the Promise executor""",
"stream idle watchdog fired",
"client reconnect watchdog"),
    # ---- 3d. client watchdog cleanup ----
    ("client",
"""					await failed;
					if (!this.isRunning()) return;
					this.emitState("reconnecting");""",
"""					await failed;
					clearInterval(watchdog);
					if (!this.isRunning()) return;
					this.emitState("reconnecting");""",
"clearInterval(watchdog);",
"client watchdog cleanup"),
    # ---- 3e. client SSE reader liveness ----
    ("client",
"""					while (true) {
						const { done, value } = await reader.read();
						if (done) return;
						buffer += decoder.decode(value, { stream: true });""",
"""					while (true) {
						const { done, value } = await reader.read();
						if (done) return;
						wireActivity.set(signal, Date.now());
						buffer += decoder.decode(value, { stream: true });""",
"wireActivity.set(signal, Date.now());\n\t\t\t\t\t\tbuffer += decoder.decode",
"client SSE liveness tracking"),
    # ---- 3f. client SSE reader cleanup ----
    ("client",
"""				} finally {
					await reader.cancel().catch(() => void 0);
				}""",
"""				} finally {
					wireActivity.delete(signal);
					await reader.cancel().catch(() => void 0);
				}""",
"wireActivity.delete(signal);",
"client SSE liveness cleanup"),
    # ---- 3g. client mux schema heartbeat ----
    ("client",
"""			object({
				type: literal("stream/error"),
				error: rpcErrorSchema
			})
		]);
		/** HostFrame union (payload slot of a host-stream ServerRequest). */""",
"""			object({
				type: literal("stream/error"),
				error: rpcErrorSchema
			}),
			object({
				type: literal("stream/heartbeat")
			})
		]);
		/** HostFrame union (payload slot of a host-stream ServerRequest). */""",
"""object({
				type: literal("stream/heartbeat")
			})
		]);
		/** HostFrame union (payload slot of a host-stream ServerRequest). */""",
"client mux schema heartbeat"),
    # ---- 3h. client host schema heartbeat ----
    ("client",
"""			object({
				type: literal("host/remote-event"),
				event: string().min(1),
				args: array(unknown())
			}),
			object({
				type: literal("stream/error"),
				error: rpcErrorSchema
			})
		]);""",
"""			object({
				type: literal("host/remote-event"),
				event: string().min(1),
				args: array(unknown())
			}),
			object({
				type: literal("stream/error"),
				error: rpcErrorSchema
			}),
			object({
				type: literal("stream/heartbeat")
			})
		]);""",
"""object({
				type: literal("stream/heartbeat")
			})
		]);
		object({});""",
"client host schema heartbeat"),
    # ---- 3i. client WebSocket reader liveness ----
    ("client",
"""				const handleMessage = (event) => {
					let full;
					let frame;
					try {
						if (typeof event.data !== "string") throw new Error("binary WebSocket frame");""",
"""				const handleMessage = (event) => {
					/* Any wire bytes (including the server's periodic stream/heartbeat
					* frames) refresh the liveness timestamp consumed by the reconnect
					* watchdog; a socket with no traffic for WATCHDOG_IDLE_MS is treated
					* as silently dead and forced into a fresh generation. */
					wireActivity.set(signal, Date.now());
					let full;
					let frame;
					try {
						if (typeof event.data !== "string") throw new Error("binary WebSocket frame");""",
"Any wire bytes (including the server's periodic stream/heartbeat",
"client WebSocket liveness tracking"),
]

status = 0
for key, old, new, marker, label in EDITS:
    path = FILES[key]
    try:
        with open(path, encoding="utf-8") as f:
            s = f.read()
    except OSError as e:
        print(f"patch-realtime: WARN {label} — cannot read {path}: {e}", file=sys.stderr)
        status = 1
        continue
    if marker in s:
        print(f"patch-realtime: {label} already applied")
        continue
    n = s.count(old)
    if n != 1:
        print(f"patch-realtime: ERROR {label} anchor not found (count={n})", file=sys.stderr)
        status = 1
        continue
    with open(path, "w", encoding="utf-8") as f:
        f.write(s.replace(old, new, 1))
    print(f"patch-realtime: {label} applied")

if status == 0:
    print("patch-realtime: OK — all realtime patches in place")
else:
    print("patch-realtime: DONE with warnings (see above)", file=sys.stderr)
sys.exit(status)
PY
