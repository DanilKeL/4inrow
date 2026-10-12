// @vitest-environment jsdom
import { useState } from 'react';
import { afterEach, describe, expect, it, vi } from 'vitest';
import { cleanup, fireEvent, render, screen, waitFor } from '@testing-library/react';
import { SURFACES, blankDesign, type DesignLayer, type SkinDesign } from '../skins/design';
import SkinDesignEditor from './SkinDesignEditor';

const mocks = vi.hoisted(() => ({ api: vi.fn(), prepare: vi.fn() }));
vi.mock('./api', () => ({ adminApi: mocks.api }));
vi.mock('./skinImage', () => ({ prepareSkinImage: mocks.prepare }));
afterEach(() => {
  cleanup();
  vi.resetAllMocks();
});

function Harness({
  initial = blankDesign(),
  busy = vi.fn(),
}: {
  initial?: SkinDesign;
  busy?: (value: boolean) => void;
}) {
  const [design, setDesign] = useState(initial);
  return (
    <SkinDesignEditor
      design={design}
      onChange={setDesign}
      disabled={false}
      onBusyChange={busy}
      onUnauthorized={vi.fn()}
    />
  );
}
const imageLayer = (index: number): DesignLayer => ({
  id: `image-${index}`,
  kind: 'image',
  imageId: index.toString(16).padStart(64, '0'),
  x: 0.5,
  y: 0.5,
  size: 0.5,
  rotation: 0,
  opacity: 1,
  color: '#ffffff',
  tint: false,
  placement: 'single',
});

describe('skin composition editor', () => {
  it('associates each range label only with its control without announcing numeric readouts as statuses', () => {
    render(<Harness />);
    expect(screen.getByLabelText('Металличность')).toBe(
      screen.getByRole('slider', { name: 'Металличность' }),
    );
    expect(
      screen.getByRole('slider', { name: 'Металличность' }).getAttribute('aria-valuetext'),
    ).toBe('0%');
    expect(screen.queryAllByRole('status')).toEqual([]);
  });
  it('keeps controls locked until image persistence succeeds and a failed upload never adds a layer', async () => {
    const busy = vi.fn();
    mocks.prepare.mockResolvedValue('data:image/webp;base64,aW1hZ2U=');
    let rejectUpload!: (reason: Error) => void;
    mocks.api.mockReturnValueOnce(
      new Promise((_resolve, reject) => {
        rejectUpload = reject;
      }),
    );
    render(<Harness busy={busy} />);
    const input = screen.getByTestId('skin-image-upload');
    const file = new File(['image'], 'emblem.png', { type: 'image/png' });
    fireEvent.change(input, { target: { files: [file] } });
    await waitFor(() => expect(mocks.api).toHaveBeenCalledOnce());
    expect(busy).toHaveBeenLastCalledWith(true);
    expect(screen.getByRole('button', { name: 'Добавить фигуру' }).matches(':disabled')).toBe(true);
    rejectUpload(new Error('Не удалось сохранить изображение.'));
    await waitFor(() =>
      expect(screen.getByRole('alert').textContent).toBe('Не удалось сохранить изображение.'),
    );
    expect(busy).toHaveBeenLastCalledWith(false);
    expect(screen.queryByTestId('skin-layers')).toBeNull();
    mocks.api.mockResolvedValueOnce({
      id: 'a'.repeat(64),
      url: `/appearance/assets/${'a'.repeat(64)}`,
    });
    fireEvent.change(input, { target: { files: [file] } });
    await waitFor(() =>
      expect(
        screen.getByRole('button', { name: 'Редактировать слой 1: Изображение' }),
      ).toBeTruthy(),
    );
    expect(screen.queryByRole('alert')).toBeNull();
    expect(busy).toHaveBeenLastCalledWith(false);
  });
  it('reuses existing images on another surface when the unique image limit is reached', () => {
    const design = blankDesign();
    for (let index = 0; index < 16; index++)
      design.surfaces[SURFACES[1 + Math.floor(index / 4)]].layers.push(imageLayer(index));
    render(<Harness initial={design} />);
    expect(screen.getByRole('button', { name: 'Добавить изображение' }).matches(':disabled')).toBe(
      true,
    );
    fireEvent.click(screen.getByRole('button', { name: 'Добавить изображение 1 из стиля' }));
    expect(screen.getByRole('button', { name: 'Редактировать слой 1: Изображение' })).toBeTruthy();
    expect(screen.getByRole('region', { name: 'Изображения стиля' }).textContent).toContain(
      '16 / 16',
    );
    expect(mocks.api).not.toHaveBeenCalled();
  });
  it('changes surface by keyboard and preserves the independent pattern selection', () => {
    render(<Harness />);
    const board = screen.getByRole('tab', { name: 'Доска' });
    fireEvent.change(screen.getByLabelText('Узор поверхности'), { target: { value: 'marble' } });
    fireEvent.keyDown(board, { key: 'ArrowRight' });
    expect(document.activeElement).toBe(screen.getByRole('tab', { name: 'Тёмные: верх' }));
    expect((screen.getByLabelText('Узор поверхности') as HTMLSelectElement).value).toBe('none');
    fireEvent.keyDown(document.activeElement!, { key: 'Home' });
    expect(document.activeElement).toBe(board);
    expect((screen.getByLabelText('Узор поверхности') as HTMLSelectElement).value).toBe('marble');
  });
});
