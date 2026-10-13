// @vitest-environment jsdom
import { afterEach, beforeEach, describe, expect, it } from 'vitest';
import { installGameTouchGuard } from './touchGuard';

let stop: () => void;
beforeEach(() => {
  document.documentElement.dataset.telegram = 'true';
  document.body.innerHTML =
    '<div id="root" data-game-interface="true"><h1>FOUR</h1><button>Играть</button><input><textarea></textarea><div contenteditable="true"><span>Editor</span></div><canvas></canvas></div><textarea id="clipboard"></textarea>';
  stop = installGameTouchGuard();
});
afterEach(() => {
  stop();
  delete document.documentElement.dataset.telegram;
  window.getSelection()?.removeAllRanges();
  document.body.innerHTML = '';
});
function cancelled(selector: string, type: string) {
  const event = new Event(type, { bubbles: true, cancelable: true });
  document.querySelector(selector)!.dispatchEvent(event);
  return event.defaultPrevented;
}

describe('game native touch selection', () => {
  it.each(['h1', 'button', 'canvas'])('blocks selection and callouts on %s', (selector) => {
    expect(cancelled(selector, 'selectstart')).toBe(true);
    expect(cancelled(selector, 'contextmenu')).toBe(true);
  });
  it.each(['input', '#root textarea', '[contenteditable] span', '#clipboard'])(
    'keeps normal editing and copying in %s',
    (selector) => {
      expect(cancelled(selector, 'selectstart')).toBe(false);
      expect(cancelled(selector, 'contextmenu')).toBe(false);
    },
  );
  it('does not intercept taps, rotation or pinch gestures', () => {
    for (const type of [
      'click',
      'dblclick',
      'pointerdown',
      'pointermove',
      'pointerup',
      'touchstart',
      'touchmove',
      'touchend',
    ])
      expect(cancelled('canvas', type)).toBe(false);
  });
  it('works without the Telegram SDK and removes listeners on teardown', () => {
    delete document.documentElement.dataset.telegram;
    expect(cancelled('h1', 'selectstart')).toBe(true);
    stop();
    expect(cancelled('h1', 'selectstart')).toBe(false);
    expect(cancelled('h1', 'contextmenu')).toBe(false);
  });
  function select(selector: string) {
    const range = document.createRange();
    range.selectNodeContents(document.querySelector(selector)!);
    const selection = window.getSelection()!;
    selection.removeAllRanges();
    selection.addRange(range);
    document.dispatchEvent(new Event('selectionchange'));
    return selection.toString();
  }
  it('removes native iOS ranges even without a selectstart event', () => {
    expect(select('h1')).toBe('');
    expect(select('#root')).toBe('');
  });
  it('keeps real editable ranges and clipboard fallback selection', () => {
    expect(select('[contenteditable] span')).toBe('Editor');
    document.querySelector('#clipboard')!.textContent = 'ABCDE';
    expect(select('#clipboard')).toBe('ABCDE');
  });
  it('preserves input selection when the browser reports a range on its wrapper', () => {
    const input = document.querySelector('input')!;
    input.value = 'TouchPlayer';
    input.focus();
    input.select();
    const range = document.createRange();
    range.selectNodeContents(document.querySelector('h1')!);
    window.getSelection()!.addRange(range);
    document.dispatchEvent(new Event('selectionchange'));
    expect(input.selectionStart).toBe(0);
    expect(input.selectionEnd).toBe(11);
    expect(window.getSelection()!.rangeCount).toBe(1);
  });
  it('does not affect the admin interface or selection outside the game', () => {
    document.querySelector('#root')!.removeAttribute('data-game-interface');
    expect(cancelled('h1', 'selectstart')).toBe(false);
    expect(select('h1')).toBe('FOUR');
  });
});
