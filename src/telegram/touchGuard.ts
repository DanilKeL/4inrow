/** A WebKit fallback for selection/callout gestures outside editable controls. */
export function installTelegramTouchGuard(): () => void {
  const preventSelection = (event: Event) => {
    const element =
      event.target instanceof Element
        ? event.target
        : event.target instanceof Node
          ? event.target.parentElement
          : null;
    if (!element?.closest('#root') || !document.documentElement.hasAttribute('data-telegram'))
      return;
    const editor = element.closest('[contenteditable]');
    if (
      element.closest('input, textarea') ||
      (editor && editor.getAttribute('contenteditable')?.toLowerCase() !== 'false')
    )
      return;
    event.preventDefault();
  };
  document.addEventListener('selectstart', preventSelection, true);
  document.addEventListener('contextmenu', preventSelection, true);
  return () => {
    document.removeEventListener('selectstart', preventSelection, true);
    document.removeEventListener('contextmenu', preventSelection, true);
  };
}
