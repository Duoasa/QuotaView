"use strict";
const fs = require("node:fs"),
  path = require("node:path"),
  crypto = require("node:crypto");
function fingerprint(task) {
  return crypto
    .createHash("sha256")
    .update(
      JSON.stringify([
        task.provider,
        task.id,
        task.turnId ?? task.startedAt ?? null,
      ]),
    )
    .digest("hex");
}
class DismissedTasks {
  constructor(directory) {
    this.file = path.join(directory, "dismissed-tasks.json");
    this.entries = new Map();
    try {
      const raw = fs.readFileSync(this.file, "utf8");
      if (raw.length > 1024 * 1024) throw Error("Too large");
      const data = JSON.parse(raw);
      if (Array.isArray(data))
        for (const row of data.slice(-4096))
          if (
            Array.isArray(row) &&
            /^[a-f0-9]{64}$/.test(row[0]) &&
            Number.isFinite(row[1])
          )
            this.entries.set(row[0], row[1]);
    } catch {}
  }
  has(task) {
    return this.entries.has(fingerprint(task));
  }
  dismiss(task) {
    this.entries.set(fingerprint(task), Date.now());
    while (this.entries.size > 4096)
      this.entries.delete(this.entries.keys().next().value);
    this.save();
  }
  restore() {
    this.entries.clear();
    this.save();
  }
  save() {
    fs.mkdirSync(path.dirname(this.file), { recursive: true, mode: 0o700 });
    const temporary = this.file + ".tmp";
    fs.writeFileSync(temporary, JSON.stringify([...this.entries]), {
      mode: 0o600,
    });
    fs.renameSync(temporary, this.file);
  }
}
module.exports = { DismissedTasks, fingerprint };
