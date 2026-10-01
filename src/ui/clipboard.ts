/** The legacy path also works on HTTP, where navigator.clipboard is unavailable. */
function copyWithSelection(text: string): boolean {
  const active = document.activeElement;
  const selection = window.getSelection();
  const ranges = selection
    ? Array.from({ length: selection.rangeCount }, (_, i) => selection.getRangeAt(i).cloneRange())
    : [];
  const field = document.createElement('textarea');
  field.value = text;
  field.readOnly = true;
  field.style.cssText =
    'position:fixed;top:0;left:0;width:1px;height:1px;opacity:0;font-size:16px;';
  document.body.append(field);
  try {
    field.focus({ preventScroll: true });
    field.select();
    field.setSelectionRange(0, text.length);
    return document.execCommand('copy');
  } catch {
    return false;
  } finally {
    field.remove();
    if (active instanceof HTMLElement) active.focus({ preventScroll: true });
    selection?.removeAllRanges();
    ranges.forEach((range) => selection?.addRange(range));
  }
}

export async function copyText(text: string): Promise<boolean> {
  if (navigator.clipboard?.writeText) {
    try {
      await navigator.clipboard.writeText(text);
      return true;
    } catch {
      // Some browsers expose the API but deny permission; try the user-gesture fallback.
    }
  }
  return copyWithSelection(text);
}
