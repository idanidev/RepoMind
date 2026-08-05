import { execFileSync } from "node:child_process";
import { existsSync, readFileSync } from "node:fs";
import { homedir } from "node:os";
import { join } from "node:path";

/**
 * Reads screenshots attached to a task straight from the Mac app's local store.
 *
 * The obvious alternative — committing images into the repo and linking them from the issue — is
 * worse in every direction. It grows the repository permanently, and in a *private* repo the image
 * would not even render: GitHub does not authenticate image URLs on the reader's behalf, so it
 * shows as broken. Making the repo public to fix that would publish bug screenshots, which
 * routinely contain personal data.
 *
 * So nothing is uploaded anywhere. The image is already on this machine, synced by iCloud; the
 * bridge just reads it and hands it to whoever asked.
 */

const SUPPORT_DIR = join(
  homedir(),
  "Library/Containers/idanidev.RepoMind/Data/Library/Application Support"
);
const STORE = join(SUPPORT_DIR, "default.store");
const EXTERNAL_DATA = join(SUPPORT_DIR, ".default_SUPPORT/_EXTERNAL_DATA");

export function storeIsAvailable(): boolean {
  return existsSync(STORE);
}

/** SwiftData keeps UUIDs as raw 16-byte blobs; the issue marker carries the text form. */
function uuidToBlobLiteral(uuid: string): string {
  const hex = uuid.replace(/-/g, "").toUpperCase();
  if (hex.length !== 32) throw new Error(`Not a UUID: ${uuid}`);
  return `X'${hex}'`;
}

function querySqlite(sql: string): string {
  // Read-only: this is the live store of an app that may be running, and must never be written to.
  return execFileSync("sqlite3", ["-readonly", STORE, sql], {
    encoding: "utf8",
    maxBuffer: 64 * 1024 * 1024,
    stdio: ["ignore", "pipe", "ignore"],
  }).trim();
}

export interface TaskImage {
  base64: string;
  mimeType: string;
  bytes: number;
}

function sniffMimeType(buffer: Buffer): string {
  if (buffer[0] === 0xff && buffer[1] === 0xd8) return "image/jpeg";
  if (buffer[0] === 0x89 && buffer[1] === 0x50) return "image/png";
  if (buffer.subarray(0, 4).toString("ascii") === "RIFF") return "image/webp";
  return "application/octet-stream";
}

const EXTERNAL_REF_UUID = /^[0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12}$/;

/**
 * Returns the screenshot for a task, or null when it has none.
 *
 * `ZIMAGEDATA` holds either the image itself or, once it grows past Core Data's threshold, a
 * reference shaped `\x02<UUID>\x00` naming a file in the external-data directory.
 */
export function readTaskImage(taskUUID: string): TaskImage | null {
  if (!storeIsAvailable()) return null;

  const raw = querySqlite(
    `SELECT quote(ZIMAGEDATA) FROM ZTASKITEM WHERE ZID = ${uuidToBlobLiteral(taskUUID)} LIMIT 1;`
  );
  if (!raw || raw === "NULL") return null;

  const hex = raw.match(/^X'([0-9A-Fa-f]*)'$/)?.[1];
  if (!hex) return null;
  const stored = Buffer.from(hex, "hex");
  if (stored.length === 0) return null;

  const asText = stored.subarray(1, stored.length - 1).toString("ascii");
  const isExternalRef = stored[0] === 0x02 && EXTERNAL_REF_UUID.test(asText);

  let image: Buffer;
  if (isExternalRef) {
    const path = join(EXTERNAL_DATA, asText);
    if (!existsSync(path)) return null;
    image = readFileSync(path);
  } else {
    image = stored;
  }

  if (image.length === 0) return null;
  return {
    base64: image.toString("base64"),
    mimeType: sniffMimeType(image),
    bytes: image.length,
  };
}

/** Whether a task has a screenshot, without paying to read it. */
export function taskHasImage(taskUUID: string): boolean {
  if (!storeIsAvailable()) return false;
  try {
    return querySqlite(
      `SELECT ZIMAGEDATA IS NOT NULL FROM ZTASKITEM WHERE ZID = ${uuidToBlobLiteral(taskUUID)} LIMIT 1;`
    ) === "1";
  } catch {
    return false;
  }
}

/** The `<!-- repomind-task:UUID -->` marker the iOS app writes into every issue body. */
export function taskUUIDFromBody(body: string | null): string | null {
  return body?.match(/<!--\s*repomind-task:([0-9A-Fa-f-]{36})\s*-->/)?.[1] ?? null;
}
