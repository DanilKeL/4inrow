// @vitest-environment jsdom
import { afterEach, beforeAll, describe, expect, it, vi } from 'vitest';
import { cleanup, fireEvent, render, screen } from '@testing-library/react';
import { Dialog } from './Dialog';

afterEach(cleanup);
// jsdom does not implement PointerEvent yet.
beforeAll(() => {
  class TestPointerEvent extends MouseEvent {
    pointerId = 1;
    isPrimary = true;
  }
  vi.stubGlobal('PointerEvent', TestPointerEvent);
});

describe('keyboard dialog access', () => {
  it('focuses the dialog, traps Tab in both directions and restores the trigger', () => {
    const trigger = document.createElement('button');
    document.body.append(trigger);
    trigger.focus();
    const close = vi.fn();
    const view = render(
      <Dialog title="Настройки" onClose={close}>
        <input aria-label="Имя" />
        <button>Готово</button>
      </Dialog>,
    );
    const first = screen.getByRole('button', { name: 'Закрыть' });
    const last = screen.getByRole('button', { name: 'Готово' });
    expect(document.activeElement).toBe(screen.getByRole('dialog'));
    fireEvent.keyDown(screen.getByRole('dialog'), { key: 'Tab' });
    expect(document.activeElement).toBe(first);
    fireEvent.keyDown(first, { key: 'Tab', shiftKey: true });
    expect(document.activeElement).toBe(last);
    fireEvent.keyDown(last, { key: 'Tab' });
    expect(document.activeElement).toBe(first);
    fireEvent.keyDown(first, { key: 'Escape' });
    expect(close).toHaveBeenCalledOnce();
    view.unmount();
    expect(document.activeElement).toBe(trigger);
    trigger.remove();
  });

  it('does not close while interacting inside the dialog', () => {
    const close = vi.fn();
    render(
      <Dialog title="Новая игра" onClose={close}>
        <input aria-label="Имя" />
      </Dialog>,
    );
    fireEvent.pointerDown(screen.getByRole('textbox', { name: 'Имя' }));
    expect(close).not.toHaveBeenCalled();
    fireEvent.click(screen.getByRole('button', { name: 'Закрыть' }));
    expect(close).toHaveBeenCalledOnce();
  });

  it('closes only after a completed backdrop tap, not a drag, cancelled or background gesture', () => {
    const close = vi.fn();
    render(
      <Dialog title="Профиль" onClose={close}>
        Профиль
      </Dialog>,
    );
    const backdrop = screen.getByRole('dialog').parentElement!;
    const position = { clientX: 20, clientY: 40, button: 0 };
    fireEvent.pointerDown(backdrop, position);
    expect(close).not.toHaveBeenCalled();
    fireEvent.pointerCancel(backdrop, position);
    fireEvent.pointerUp(backdrop, position);
    fireEvent.click(backdrop);
    fireEvent.pointerDown(backdrop, position);
    fireEvent.pointerMove(backdrop, { ...position, clientY: 80 });
    fireEvent.pointerUp(backdrop, position);
    fireEvent.click(backdrop);
    fireEvent.pointerDown(backdrop, position);
    fireEvent(document, new Event('visibilitychange'));
    fireEvent.pointerUp(backdrop, position);
    fireEvent.click(backdrop);
    expect(close).not.toHaveBeenCalled();
    fireEvent.pointerDown(backdrop, position);
    fireEvent.pointerUp(backdrop, position);
    expect(close).not.toHaveBeenCalled();
    fireEvent.click(backdrop);
    expect(close).toHaveBeenCalledOnce();
  });

  it('consumes the final backdrop click instead of bubbling it to the menu', () => {
    const close = vi.fn();
    const menuClick = vi.fn();
    render(
      <div onClick={menuClick}>
        <Dialog title="Настройки" onClose={close}>
          Настройки
        </Dialog>
      </div>,
    );
    const backdrop = screen.getByRole('dialog').parentElement!;
    const position = { clientX: 20, clientY: 40, button: 0 };
    fireEvent.pointerDown(backdrop, position);
    fireEvent.pointerUp(backdrop, position);
    expect(close).not.toHaveBeenCalled();
    expect(fireEvent.click(backdrop)).toBe(false);
    expect(close).toHaveBeenCalledOnce();
    expect(menuClick).not.toHaveBeenCalled();
  });
});
