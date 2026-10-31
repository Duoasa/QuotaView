"use strict";
const terminal = new Set(["completed", "failed", "interrupted", "error"]);
const active = new Set(["thinking", "working", "waiting", "compacting"]);

// Notifications and completion expansion consume the same one-shot event.
// Initial history is a baseline, not a newly finished task. Keep tombstones
// across temporary disappearance, connection changes and disabled notifications.
class CompletionLedger {
  constructor() { this.turns = new Map(); }
  observe(task) {
    const key = JSON.stringify([task.provider, task.id, task.turnId ?? task.startedAt ?? "legacy"]);
    let entry = this.turns.get(key);
    if (!entry) {
      entry = { active: false, settled: false };
      this.turns.set(key, entry);
      if (this.turns.size > 8192) this.turns.delete(this.turns.keys().next().value);
    }
    if (terminal.has(task.status) && task.verified !== false) {
      const completed = entry.active && !entry.settled;
      entry.settled = true;
      return completed;
    }
    if (active.has(task.status) && task.verified !== false) entry.active = true;
    return false;
  }
}
module.exports = { CompletionLedger, terminal };
