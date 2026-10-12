// @vitest-environment jsdom
import { afterEach, expect, it, vi } from 'vitest';
import { cleanup, fireEvent, render, screen } from '@testing-library/react';
import { StrictMode } from 'react';
import { useBackgroundState } from './useBackgroundState';

const valid = (value: unknown): value is string => value === 'overview' || value === 'security';
function Tabs({ enabled = true }: { enabled?: boolean }) {
  const [tab, setTab] = useBackgroundState('test-navigation', 'overview', valid, enabled);
  return <button onClick={() => setTab('security')}>{tab}</button>;
}
afterEach(() => {
  cleanup();
  sessionStorage.clear();
  vi.restoreAllMocks();
});

it('keeps tabs during backgrounding and restores them after the browser discards the page', () => {
  const hidden = vi.spyOn(document, 'hidden', 'get').mockReturnValue(false);
  const view = render(
    <StrictMode>
      <Tabs />
    </StrictMode>,
  );
  fireEvent.click(screen.getByRole('button', { name: 'overview' }));
  hidden.mockReturnValue(true);
  fireEvent(document, new Event('visibilitychange'));
  expect(screen.getByRole('button', { name: 'security' })).toBeDefined();
  expect(sessionStorage.getItem('test-navigation')).toBe('"security"');
  view.unmount();
  hidden.mockReturnValue(false);
  render(
    <StrictMode>
      <Tabs />
    </StrictMode>,
  );
  expect(screen.getByRole('button', { name: 'security' })).toBeDefined();
  expect(sessionStorage.getItem('test-navigation')).toBeNull();
});

it('drops the checkpoint when returning to the existing page and saves on pagehide', () => {
  const hidden = vi.spyOn(document, 'hidden', 'get').mockReturnValue(false);
  render(<Tabs />);
  fireEvent.click(screen.getByRole('button'));
  hidden.mockReturnValue(true);
  fireEvent(document, new Event('visibilitychange'));
  hidden.mockReturnValue(false);
  fireEvent(document, new Event('visibilitychange'));
  expect(sessionStorage.getItem('test-navigation')).toBeNull();
  expect(screen.getByRole('button', { name: 'security' })).toBeDefined();
  fireEvent(window, new Event('pagehide'));
  expect(sessionStorage.getItem('test-navigation')).toBe('"security"');
});

it('rejects invalid state and gives account recovery links precedence', () => {
  sessionStorage.setItem('test-navigation', '"invalid"');
  const view = render(<Tabs />);
  expect(screen.getByRole('button', { name: 'overview' })).toBeDefined();
  view.unmount();
  sessionStorage.setItem('test-navigation', '"security"');
  render(<Tabs enabled={false} />);
  expect(screen.getByRole('button', { name: 'overview' })).toBeDefined();
});
