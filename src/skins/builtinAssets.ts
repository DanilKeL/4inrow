/** Immutable stock artwork. The id hashes the exact shipped image bytes. */
export const ANIME_HEROINE_IMAGE_ID =
  'bc22fbff3d878f25892d3bd09227dfe92c943adfabbbe88309788c40eceed6fb';
const images: Readonly<Record<string, string>> = {
  [ANIME_HEROINE_IMAGE_ID]: '/skins/moonlit-sakura-bc22fbff3d87.webp',
};
export function builtinSkinImageUrl(id: string): string | undefined {
  return Object.hasOwn(images, id) ? images[id] : undefined;
}
