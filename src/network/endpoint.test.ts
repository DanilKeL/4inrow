import { describe, expect, it } from 'vitest';
import { onlineEndpoint } from './endpoint';

describe('online endpoint', () => {
  it('keeps browser games on their own server', () => {
    expect(onlineEndpoint({ protocol: 'http:', host: 'localhost:5173' }, '')).toBe(
      'ws://localhost:5173/online',
    );
    expect(onlineEndpoint({ protocol: 'https:', host: 'game.example' }, '')).toBe(
      'wss://game.example/online',
    );
  });
  it('uses a configured online server', () => {
    expect(
      onlineEndpoint({ protocol: 'http:', host: 'localhost' }, 'ws://116.206.95.180/online'),
    ).toBe('ws://116.206.95.180/online');
  });
  it('rejects invalid WebSocket protocols', () => {
    expect(() =>
      onlineEndpoint({ protocol: 'http:', host: 'localhost' }, 'https://game.example/online'),
    ).toThrow();
  });
});
