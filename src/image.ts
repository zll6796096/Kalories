export const MAX_DECODED_IMAGE_BYTES = 3 * 1024 * 1024;
export const MAX_REQUEST_BODY_BYTES = 4 * 1024 * 1024;
export const MAX_IMAGE_EDGE = 1600;
export const MAX_PREPARED_IMAGE_PIXELS = MAX_IMAGE_EDGE * MAX_IMAGE_EDGE;

const supportedMimeTypes = new Set([
  'image/jpeg',
  'image/png',
  'image/webp',
] as const);

type SupportedMimeType = 'image/jpeg' | 'image/png' | 'image/webp';
type ImagePreparationErrorCode =
  | 'INVALID_IMAGE'
  | 'UNSUPPORTED_IMAGE'
  | 'IMAGE_TOO_LARGE';

export class ImagePreparationError extends Error {
  readonly code: ImagePreparationErrorCode;

  constructor(code: ImagePreparationErrorCode) {
    super(code);
    this.name = 'ImagePreparationError';
    this.code = code;
  }
}

export interface ParsedImageDataUrl {
  mimeType: SupportedMimeType;
  base64: string;
}

export interface ImageDimensions {
  width: number;
  height: number;
}

export interface LoadedImage {
  width: number;
  height: number;
  source: unknown;
}

export interface ImagePreparationRuntime {
  load: (dataUrl: string) => Promise<LoadedImage>;
  encode: (
    source: unknown,
    width: number,
    height: number,
    quality: number,
  ) => string;
}

const base64Pattern =
  /^(?:[A-Za-z0-9+/]{4})*(?:[A-Za-z0-9+/]{2}==|[A-Za-z0-9+/]{3}=)?$/;

export function decodedBase64ByteLength(base64: string): number {
  if (!base64 || !base64Pattern.test(base64)) {
    throw new ImagePreparationError('INVALID_IMAGE');
  }

  const padding = base64.endsWith('==') ? 2 : base64.endsWith('=') ? 1 : 0;
  return (base64.length / 4) * 3 - padding;
}

export function parseImageDataUrl(dataUrl: string): ParsedImageDataUrl {
  const match = /^data:([^;,]+);base64,([A-Za-z0-9+/]+={0,2})$/.exec(
    dataUrl,
  );
  if (!match) {
    throw new ImagePreparationError('INVALID_IMAGE');
  }

  const mimeType = match[1].toLowerCase();
  if (!supportedMimeTypes.has(mimeType as SupportedMimeType)) {
    throw new ImagePreparationError('UNSUPPORTED_IMAGE');
  }

  const base64 = match[2];
  decodedBase64ByteLength(base64);
  return {mimeType: mimeType as SupportedMimeType, base64};
}

export function fitWithinDimensions(
  width: number,
  height: number,
  maxEdge = MAX_IMAGE_EDGE,
  maxPixels = MAX_PREPARED_IMAGE_PIXELS,
): ImageDimensions {
  if (
    !Number.isFinite(width) ||
    !Number.isFinite(height) ||
    !Number.isFinite(maxEdge) ||
    !Number.isFinite(maxPixels) ||
    width <= 0 ||
    height <= 0 ||
    maxEdge <= 0 ||
    maxPixels <= 0
  ) {
    throw new ImagePreparationError('INVALID_IMAGE');
  }

  const edgeScale = Math.min(1, maxEdge / Math.max(width, height));
  const pixelScale = Math.min(1, Math.sqrt(maxPixels / (width * height)));
  const scale = Math.min(edgeScale, pixelScale);

  return {
    width: Math.max(1, Math.floor(width * scale)),
    height: Math.max(1, Math.floor(height * scale)),
  };
}

function requestBodyByteLength(dataUrl: string): number {
  return new TextEncoder().encode(JSON.stringify({image: dataUrl})).byteLength;
}

export function isWithinAnalysisLimits(dataUrl: string): boolean {
  try {
    const {base64} = parseImageDataUrl(dataUrl);
    return (
      decodedBase64ByteLength(base64) <= MAX_DECODED_IMAGE_BYTES &&
      requestBodyByteLength(dataUrl) < MAX_REQUEST_BODY_BYTES
    );
  } catch {
    return false;
  }
}

function loadBrowserImage(dataUrl: string): Promise<LoadedImage> {
  if (typeof Image === 'undefined') {
    return Promise.reject(new ImagePreparationError('INVALID_IMAGE'));
  }

  return new Promise((resolve, reject) => {
    const image = new Image();
    image.onload = () =>
      resolve({
        width: image.naturalWidth || image.width,
        height: image.naturalHeight || image.height,
        source: image,
      });
    image.onerror = () =>
      reject(new ImagePreparationError('INVALID_IMAGE'));
    image.src = dataUrl;
  });
}

function encodeBrowserImage(
  source: unknown,
  width: number,
  height: number,
  quality: number,
): string {
  if (typeof document === 'undefined') {
    throw new ImagePreparationError('INVALID_IMAGE');
  }

  const canvas = document.createElement('canvas');
  canvas.width = width;
  canvas.height = height;
  const context = canvas.getContext('2d');
  if (!context) {
    throw new ImagePreparationError('INVALID_IMAGE');
  }

  context.fillStyle = '#ffffff';
  context.fillRect(0, 0, width, height);
  context.drawImage(source as CanvasImageSource, 0, 0, width, height);
  return canvas.toDataURL('image/jpeg', quality);
}

const browserImageRuntime: ImagePreparationRuntime = {
  load: loadBrowserImage,
  encode: encodeBrowserImage,
};

function ownedPreparationError(error: unknown): ImagePreparationError {
  return error instanceof ImagePreparationError
    ? error
    : new ImagePreparationError('INVALID_IMAGE');
}

export async function prepareImageForAnalysis(
  dataUrl: string,
  runtime: ImagePreparationRuntime = browserImageRuntime,
): Promise<string> {
  parseImageDataUrl(dataUrl);

  let source: LoadedImage;
  try {
    source = await runtime.load(dataUrl);
  } catch (error) {
    throw ownedPreparationError(error);
  }

  const fitted = fitWithinDimensions(source.width, source.height);

  const scales = [1, 0.85, 0.7, 0.55];
  const qualities = [0.82, 0.68, 0.54];

  try {
    for (const scale of scales) {
      const width = Math.max(1, Math.floor(fitted.width * scale));
      const height = Math.max(1, Math.floor(fitted.height * scale));

      for (const quality of qualities) {
        const prepared = runtime.encode(
          source.source,
          width,
          height,
          quality,
        );
        if (isWithinAnalysisLimits(prepared)) {
          return prepared;
        }
      }
    }
  } catch (error) {
    throw ownedPreparationError(error);
  }

  throw new ImagePreparationError('IMAGE_TOO_LARGE');
}
