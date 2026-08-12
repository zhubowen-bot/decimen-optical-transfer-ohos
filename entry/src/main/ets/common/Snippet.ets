import { util } from '@kit.ArkTS';
import { packFile } from './Protocol';
import type { OpticalFile, PackedOpticalFile } from './Protocol';

export const SNIPPET_MEDIA_TYPE: string = 'application/vnd.decimen.snippet';
export const SNIPPET_FILE_NAME: string = 'snippet.txt';
export const MAX_SNIPPET_BYTES: number = 4 * 1024 * 1024;
export const MAX_SNIPPET_LABEL: string = `${MAX_SNIPPET_BYTES / 1024 / 1024} MB`;

const decoder: util.TextDecoder = new util.TextDecoder('utf-8', { fatal: true });

export function isSnippet(file: OpticalFile): boolean {
  return file.type === SNIPPET_MEDIA_TYPE;
}

export async function packSnippet(text: string): Promise<PackedOpticalFile> {
  if (text.trim().length === 0) {
    throw new Error('Paste or type some text before sending.');
  }
  const encoder: util.TextEncoder = new util.TextEncoder();
  const bytes: Uint8Array = encoder.encode(text);
  if (bytes.length > MAX_SNIPPET_BYTES) {
    throw new Error(`Text snippets are limited to ${MAX_SNIPPET_LABEL}.`);
  }
  return packFile(SNIPPET_FILE_NAME, SNIPPET_MEDIA_TYPE, bytes);
}

export function snippetText(file: OpticalFile): string {
  if (!isSnippet(file)) {
    throw new Error('This stream is not a text snippet.');
  }
  return decoder.decodeToString(file.bytes);
}
