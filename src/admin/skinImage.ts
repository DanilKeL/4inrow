const MAX_INPUT_BYTES = 16 * 1024 * 1024;
const MAX_OUTPUT_BYTES = 512 * 1024;
const MAX_DIMENSION = 1024;

export function rasterMime(bytes: Uint8Array): string | null {
  if (
    bytes.length >= 8 &&
    [137, 80, 78, 71, 13, 10, 26, 10].every((byte, index) => bytes[index] === byte)
  )
    return 'image/png';
  if (bytes.length >= 3 && bytes[0] === 255 && bytes[1] === 216 && bytes[2] === 255)
    return 'image/jpeg';
  if (
    bytes.length >= 12 &&
    String.fromCharCode(...bytes.slice(0, 4)) === 'RIFF' &&
    String.fromCharCode(...bytes.slice(8, 12)) === 'WEBP'
  )
    return 'image/webp';
  return null;
}

export function imageDimensions(width: number, height: number, limit = MAX_DIMENSION) {
  if (
    !Number.isFinite(width) ||
    !Number.isFinite(height) ||
    width < 1 ||
    height < 1 ||
    width > 16384 ||
    height > 16384
  )
    throw new Error('Изображение должно быть не больше 16384 × 16384 пикселей.');
  const scale = Math.min(1, limit / Math.max(width, height));
  return {
    width: Math.max(1, Math.round(width * scale)),
    height: Math.max(1, Math.round(height * scale)),
  };
}

function asDataUrl(blob: Blob): Promise<string> {
  return new Promise((resolve, reject) => {
    const reader = new FileReader();
    reader.onload = () => resolve(String(reader.result));
    reader.onerror = () => reject(new Error('Не удалось прочитать изображение.'));
    reader.readAsDataURL(blob);
  });
}

/** Decode and re-encode locally; never send unvalidated original bytes or an SVG. */
export async function prepareSkinImage(file: File): Promise<string> {
  if (!file.size || file.size > MAX_INPUT_BYTES)
    throw new Error('Выберите PNG, JPEG или WebP размером до 16 МБ.');
  const signature = new Uint8Array(await file.slice(0, 12).arrayBuffer());
  const mime = rasterMime(signature);
  if (!mime) throw new Error('Поддерживаются только PNG, JPEG и WebP.');
  const source = new Blob([await file.arrayBuffer()], { type: mime });
  const url = URL.createObjectURL(source);
  try {
    const image = new Image();
    image.src = url;
    try {
      await image.decode();
    } catch {
      throw new Error('Не удалось открыть изображение. Попробуйте другой файл.');
    }
    const size = imageDimensions(image.naturalWidth, image.naturalHeight);
    const canvas = document.createElement('canvas');
    const context = canvas.getContext('2d');
    if (!context) throw new Error('Браузер не поддерживает обработку изображений.');
    for (const [scale, quality] of [
      [1, 0.9],
      [1, 0.75],
      [0.8, 0.75],
      [0.6, 0.7],
    ] as const) {
      canvas.width = Math.max(1, Math.round(size.width * scale));
      canvas.height = Math.max(1, Math.round(size.height * scale));
      context.drawImage(image, 0, 0, canvas.width, canvas.height);
      const blob = await new Promise<Blob | null>((resolve) =>
        canvas.toBlob(resolve, 'image/webp', quality),
      );
      if (
        blob &&
        ['image/webp', 'image/png', 'image/jpeg'].includes(blob.type) &&
        blob.size <= MAX_OUTPUT_BYTES
      )
        return await asDataUrl(blob);
    }
    throw new Error('Изображение слишком сложное. Уменьшите его размер и попробуйте снова.');
  } finally {
    URL.revokeObjectURL(url);
  }
}
