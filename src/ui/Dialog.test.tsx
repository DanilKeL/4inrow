// @vitest-environment jsdom
import { afterEach, describe, expect, it, vi } from 'vitest';
import { cleanup, fireEvent, render, screen } from '@testing-library/react';
import { Dialog } from './Dialog';

afterEach(cleanup);

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
});
