// ─── Prism — Frontend Logger ──────────────────────────────────────────
// Ring-buffer logger with console output and optional backend flush.
// Exposed as `window.__prismLogger` before app.js loads.

(function () {
  'use strict';

  const LEVELS = { DEBUG: 0, INFO: 1, WARN: 2, ERROR: 3 };
  const LEVEL_LABELS = ['DEBUG', 'INFO', 'WARN', 'ERROR'];
  const MAX_BUFFER = 500;
  const BACKEND_FLUSH_THRESHOLD = 10; // flush when this many WARN+ entries accumulate

  class Logger {
    constructor() {
      this._buffer = [];
      this._level = LEVELS.DEBUG;
      this._pendingFlush = [];
      this._flushTimer = null;
      this._backendReady = false;
      this._disabled = false;
    }

    // ── Public API ──────────────────────────────────────────────

    setLevel(level) {
      if (typeof level === 'string') {
        this._level = LEVELS[level.toUpperCase()] ?? LEVELS.DEBUG;
      } else if (typeof level === 'number') {
        this._level = level;
      }
    }

    /**
     * Disable all logging (console + backend flush).
     */
    disable() {
      this._disabled = true;
      this._level = LEVELS.ERROR + 999; // effectively off
    }

    /**
     * Re-enable logging at the given level (default: DEBUG).
     */
    enable(level) {
      this._disabled = false;
      this._level = (typeof level === 'string')
        ? (LEVELS[level.toUpperCase()] ?? LEVELS.DEBUG)
        : (typeof level === 'number' ? level : LEVELS.DEBUG);
    }

    isEnabled() { return !this._disabled; }

    getLevel() { return this._level; }

    debug(tag, msg, data) { this._log(LEVELS.DEBUG, tag, msg, data); }
    info(tag, msg, data)  { this._log(LEVELS.INFO, tag, msg, data); }
    warn(tag, msg, data)  { this._log(LEVELS.WARN, tag, msg, data); }
    error(tag, msg, data) { this._log(LEVELS.ERROR, tag, msg, data); }

    /**
     * Return a copy of all buffered entries.
     */
    getBuffer() {
      return this._buffer.slice();
    }

    /**
     * Export buffered entries as formatted text (for copy / debug).
     */
    exportText() {
      return this._buffer.map(e =>
        `[${e.timestamp}] [${e.levelLabel}] [${e.tag}] ${e.message}`
      ).join('\n');
    }

    /**
     * Mark backend as ready — enables flush-to-file.
     */
    setBackendReady(ready) {
      this._backendReady = ready;
      if (ready && this._pendingFlush.length) {
        this._doFlush();
      }
    }

    // ── Internal ────────────────────────────────────────────────

    _log(level, tag, msg, data) {
      if (level < this._level) return;

      const entry = {
        timestamp: new Date().toISOString(),
        level: level,
        levelLabel: LEVEL_LABELS[level],
        tag: String(tag),
        message: String(msg),
        data: data !== undefined ? data : null
      };

      // Push to ring buffer
      this._buffer.push(entry);
      if (this._buffer.length > MAX_BUFFER) {
        this._buffer.shift();
      }

      // Console output (color-coded)
      this._consoleOut(entry);

      // Queue for backend flush (WARN+ only)
      if (level >= LEVELS.WARN) {
        this._pendingFlush.push(entry);
        this._scheduleFlush();
      }
    }

    _consoleOut(entry) {
      const prefix = `[${entry.timestamp.slice(11, 23)}] [${entry.tag}]`;
      const msg = entry.message;
      const d = entry.data;

      switch (entry.level) {
        case LEVELS.DEBUG:
          console.debug(prefix, msg, d || '');
          break;
        case LEVELS.INFO:
          console.info(prefix, msg, d || '');
          break;
        case LEVELS.WARN:
          console.warn(prefix, msg, d || '');
          break;
        case LEVELS.ERROR:
          console.error(prefix, msg, d || '');
          break;
      }
    }

    _scheduleFlush() {
      if (this._pendingFlush.length >= BACKEND_FLUSH_THRESHOLD) {
        // Flush immediately when threshold reached
        if (this._flushTimer) { clearTimeout(this._flushTimer); this._flushTimer = null; }
        this._doFlush();
      } else if (!this._flushTimer) {
        // Debounce: flush after 2s of inactivity
        this._flushTimer = setTimeout(() => {
          this._flushTimer = null;
          this._doFlush();
        }, 2000);
      }
    }

    _doFlush() {
      if (!this._backendReady || !this._pendingFlush.length) return;

      const entries = this._pendingFlush.splice(0);
      const invoke = window.__TAURI_INVOKE__;

      if (invoke) {
        invoke('log_message', { entries: entries.map(e => ({
          timestamp: e.timestamp,
          level: e.levelLabel,
          tag: e.tag,
          message: e.message,
          data: e.data ? JSON.stringify(e.data) : null
        })) }).catch(() => {
          // Silently ignore flush failures — don't create infinite loops
        });
      }
    }
  }

  // ── Singleton ─────────────────────────────────────────────────
  const logger = new Logger();
  window.__prismLogger = logger;

  // Also expose a quick global helper
  window.PrismLog = {
    d: (t, m, d) => logger.debug(t, m, d),
    i: (t, m, d) => logger.info(t, m, d),
    w: (t, m, d) => logger.warn(t, m, d),
    e: (t, m, d) => logger.error(t, m, d),
    getBuffer: () => logger.getBuffer(),
    export: () => logger.exportText(),
    setBackendReady: (r) => logger.setBackendReady(r),
    enable: (l) => logger.enable(l),
    disable: () => logger.disable(),
    isEnabled: () => logger.isEnabled()
  };
})();
