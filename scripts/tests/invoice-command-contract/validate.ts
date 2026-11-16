import { readFileSync } from 'node:fs';
import { pathToFileURL } from 'node:url';
import { join } from 'node:path';
async function main() {
const web = process.env.THORBIS_WEB_ROOT!;
const dir = process.env.INVOICE_PROBE_DIR!;
const { parseInput } = await import(pathToFileURL(join(web, "packages/validation/src/index.ts")).href);
const { commandBatchSchema } = await import(pathToFileURL(join(web, "packages/sync/src/envelope.ts")).href);
const { parseUpdateInvoiceLinesIntent } = await import(pathToFileURL(join(web, "domains/invoicing/src/schemas.ts")).href);
const b=readFileSync(join(dir, 'envelope.json'));
const envelope=JSON.parse(b.toString());
const batch=parseInput(commandBatchSchema,{commands:[envelope]});
const intent=await parseUpdateInvoiceLinesIntent(batch.commands[0].payload);
const [manual, estimate, held, selected] = intent.input.lines;
if (manual.source?.kind !== 'manual' || estimate.source?.kind !== 'estimate' ||
    estimate.source.estimateLineSource?.kind !== 'manual' ||
    estimate.source.estimateLineSource.addedByUserId !== envelope.actorId ||
    held.source?.kind !== 'price_book' || !('originalDescription' in held.source) ||
    held.source.originalDescription !== 'Original' || selected.source?.kind !== 'price_book' ||
    'originalDescription' in selected.source || selected.source.priceBookRevision !== 1) {
  throw new Error('provenance did not survive parsing');
}
const limit = JSON.parse(readFileSync(join(dir, 'boundary.json'),'utf8'));
parseInput(commandBatchSchema,{commands:[limit]});
await parseUpdateInvoiceLinesIntent(limit.payload);
const limitJS = Buffer.byteLength(JSON.stringify(limit));
limit.payload.lines[0].description += 'a';
let rejected = false; try { parseInput(commandBatchSchema,{commands:[limit]}); } catch { rejected = true }
if (limitJS !== 65536 || !rejected) throw new Error('boundary mismatch');
console.log('real-model boundary server accepted 65536, rejected 65537');
console.log(JSON.stringify({swiftBytes:b.length, jsBytes:Buffer.byteLength(JSON.stringify(envelope)),sources:intent.input.lines.map(l=>l.source?.kind),fingerprint:intent.fingerprint}));

}
main().catch(e => { console.error(e); process.exitCode=1 });
