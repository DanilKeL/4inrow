/** Blocks WebKit text-selection gestures on the game UI, including Safari and Mini Apps. */
export function installGameTouchGuard(): () => void {
  const elementFor = (node: EventTarget | null): Element | null =>
    node instanceof Element ? node : node instanceof Node ? node.parentElement : null;
  const editable = (node: EventTarget | null): boolean => {
    const element = elementFor(node);
    if (element?.closest('input, textarea')) return true;
    const editor = element?.closest('[contenteditable]');
    return Boolean(editor && editor.getAttribute('contenteditable')?.toLowerCase() !== 'false');
  };
  const preventSelection = (event: Event) => {
    if (elementFor(event.target)?.closest('#root[data-game-interface]') && !editable(event.target))
      event.preventDefault();
  };
  const clearNativeSelection = () => {
    const selection = window.getSelection();
    const root = document.querySelector('#root[data-game-interface]');
    if (
      !root ||
      !selection?.rangeCount ||
      editable(document.activeElement) ||
      editable(selection.anchorNode) ||
      editable(selection.focusNode)
    )
      return;
    // iOS can start native selection without emitting a cancelable selectstart.
    // Clear the real range too, including ranges spanning the whole game surface.
    for (let index = 0; index < selection.rangeCount; index++) {
      if (selection.getRangeAt(index).intersectsNode(root)) {
        selection.removeAllRanges();
        return;
      }
    }
  };
  document.addEventListener('selectstart', preventSelection, true);
  document.addEventListener('contextmenu', preventSelection, true);
  document.addEventListener('selectionchange', clearNativeSelection);
  return () => {
    document.removeEventListener('selectstart', preventSelection, true);
    document.removeEventListener('contextmenu', preventSelection, true);
    document.removeEventListener('selectionchange', clearNativeSelection);
  };
}
