// @vitest-environment jsdom
import { afterEach, beforeEach, describe, expect, it } from 'vitest';
import { installTelegramTouchGuard } from './touchGuard';

let stop: () => void;
beforeEach(() => {
  document.documentElement.dataset.telegram = 'true';
  document.body.innerHTML =
    '<div id="root"><h1>FOUR</h1><button>Играть</button><input><textarea></textarea><div contenteditable="true"><span>Editor</span></div><canvas></canvas></div><textarea id="clipboard"></textarea>';
  stop = installTelegramTouchGuard();
});
afterEach(() => {
  stop();
  delete document.documentElement.dataset.telegram;
  document.body.innerHTML = '';
});
function cancelled(selector: string, type: string) {
  const event = new Event(type, { bubbles: true, cancelable: true });
  document.querySelector(selector)!.dispatchEvent(event);
  return event.defaultPrevented;
}

describe('Telegram native touch selection', () => {
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
  it('leaves the normal website alone and removes listeners on teardown', () => {
    delete document.documentElement.dataset.telegram;
    expect(cancelled('h1', 'selectstart')).toBe(false);
    document.documentElement.dataset.telegram = 'true';
    stop();
    expect(cancelled('h1', 'selectstart')).toBe(false);
    expect(cancelled('h1', 'contextmenu')).toBe(false);
  });
});
