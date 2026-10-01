// @vitest-environment jsdom
import { afterEach, describe, expect, it, vi } from 'vitest';
import { copyText } from './clipboard';

afterEach(() => {
  vi.restoreAllMocks();
  document.body.replaceChildren();
});

describe('lobby clipboard', () => {
  it('writes through the secure Clipboard API', async () => {
    const writeText = vi.fn().mockResolvedValue(undefined);
    Object.defineProperty(navigator, 'clipboard', { configurable: true, value: { writeText } });
    expect(await copyText('ABCDE')).toBe(true);
    expect(writeText).toHaveBeenCalledWith('ABCDE');
  });

  it.each(['missing', 'denied'])(
    'copies the selected code when Clipboard API is %s',
    async (mode) => {
      Object.defineProperty(navigator, 'clipboard', {
        configurable: true,
        value:
          mode === 'missing'
            ? undefined
            : { writeText: vi.fn().mockRejectedValue(new Error('Denied')) },
      });
      const button = document.createElement('button');
      document.body.append(button);
      button.focus();
      const execCommand = vi.fn(() => {
        const field = document.activeElement as HTMLTextAreaElement;
        expect(field.value).toBe('ABCDE');
        expect(field.selectionStart).toBe(0);
        expect(field.selectionEnd).toBe(5);
        return true;
      });
      Object.defineProperty(document, 'execCommand', { configurable: true, value: execCommand });
      expect(await copyText('ABCDE')).toBe(true);
      expect(execCommand).toHaveBeenCalledWith('copy');
      expect(document.querySelector('textarea')).toBeNull();
      expect(document.activeElement).toBe(button);
    },
  );

  it('does not report success when both copy paths fail', async () => {
    Object.defineProperty(navigator, 'clipboard', { configurable: true, value: undefined });
    Object.defineProperty(document, 'execCommand', { configurable: true, value: () => false });
    expect(await copyText('ABCDE')).toBe(false);
    expect(document.querySelector('textarea')).toBeNull();
  });
});
