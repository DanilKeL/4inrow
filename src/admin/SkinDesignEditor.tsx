import { useId, useRef, useState } from 'react';
import { ArrowDown, ArrowUp, Copy, ImagePlus, LoaderCircle, Plus, Trash2 } from 'lucide-react';
import {
  MOTIFS,
  PATTERNS,
  MAX_DESIGN_IMAGES,
  blankDesign,
  designImageIds,
  imageLayer,
  motifLayer,
  type DesignLayer,
  type Motif,
  type Pattern,
  type Placement,
  type SkinDesign,
  type SurfaceDesign,
  type SurfaceName,
} from '../skins/design';
import { adminApi } from './api';
import { prepareSkinImage } from './skinImage';
import styles from './SkinDesignEditor.module.css';

const surfaces: [SurfaceName, string][] = [
  ['board', 'Доска'],
  ['darkCap', 'Тёмные: верх'],
  ['lightCap', 'Светлые: верх'],
  ['darkBody', 'Тёмные: боковина'],
  ['lightBody', 'Светлые: боковина'],
];
const patternNames: Record<Pattern, string> = {
  none: 'Без узора',
  celestial: 'Небесный атлас',
  botanical: 'Ботаника',
  artdeco: 'Арт-деко',
  guilloche: 'Гильоше',
  marble: 'Мрамор',
};
const motifNames: Record<Motif, string> = {
  moon: 'Луна',
  sun: 'Солнце',
  star: 'Звезда',
  lotus: 'Лотос',
  laurel: 'Лавр',
  diamond: 'Ромб',
  rings: 'Кольца',
};
const layerName = (layer: DesignLayer) =>
  layer.kind === 'motif' ? motifNames[layer.motif] : 'Изображение';
const freshId = () => crypto.randomUUID();

function Slider({
  label,
  value,
  min = 0,
  max = 1,
  step = 0.01,
  suffix = '%',
  onChange,
}: {
  label: string;
  value: number;
  min?: number;
  max?: number;
  step?: number;
  suffix?: string;
  onChange: (value: number) => void;
}) {
  const sliderId = useId();
  const percentage = suffix === '%';
  const displayValue = percentage ? Math.round(value * 100) : Math.round(value * 100) / 100;
  return (
    <div className={styles.slider}>
      <span>
        <label htmlFor={sliderId}>{label}</label>
        <output aria-hidden="true" role="presentation">
          {displayValue}
          {suffix}
        </output>
      </span>
      <input
        id={sliderId}
        type="range"
        aria-label={label}
        aria-valuetext={`${displayValue}${suffix}`}
        min={min}
        max={max}
        step={step}
        value={value}
        onChange={(event) => onChange(Number(event.target.value))}
      />
    </div>
  );
}

export default function SkinDesignEditor({
  design,
  onChange,
  disabled,
  onBusyChange,
  onUnauthorized,
}: {
  design: SkinDesign;
  onChange: (design: SkinDesign) => void;
  disabled: boolean;
  onBusyChange: (busy: boolean) => void;
  onUnauthorized: () => void;
}) {
  const [surface, setSurface] = useState<SurfaceName>('board');
  const [selectedId, setSelectedId] = useState<string | null>(null);
  const [motif, setMotif] = useState<Motif>('moon');
  const [uploading, setUploading] = useState(false);
  const [error, setError] = useState('');
  const fileInput = useRef<HTMLInputElement>(null);
  const part = design.surfaces[surface];
  const images = designImageIds(design);
  const selected = part.layers.find((layer) => layer.id === selectedId) ?? part.layers[0];
  const locked = disabled || uploading;
  const updateSurface = (patch: Partial<SurfaceDesign>) =>
    onChange({ ...design, surfaces: { ...design.surfaces, [surface]: { ...part, ...patch } } });
  const updateLayer = (patch: Partial<DesignLayer>) => {
    if (!selected) return;
    updateSurface({
      layers: part.layers.map((layer) =>
        layer.id === selected.id ? ({ ...layer, ...patch } as DesignLayer) : layer,
      ),
    });
  };
  const appendLayer = (layer: DesignLayer) => {
    updateSurface({ layers: [...part.layers, layer] });
    setSelectedId(layer.id);
  };
  const appendImage = (imageId: string) => appendLayer(imageLayer(imageId, part.ink, freshId()));
  const moveLayer = (id: string, direction: number) => {
    const next = [...part.layers];
    const index = next.findIndex((layer) => layer.id === id);
    const destination = index + direction;
    if (index < 0 || destination < 0 || destination >= next.length) return;
    [next[index], next[destination]] = [next[destination], next[index]];
    updateSurface({ layers: next });
  };
  async function upload(file?: File) {
    if (!file || locked || part.layers.length >= 12) return;
    if (images.length >= MAX_DESIGN_IMAGES) {
      setError(
        `В одном стиле можно использовать до ${MAX_DESIGN_IMAGES} разных изображений. Выберите уже загруженное изображение ниже.`,
      );
      return;
    }
    setUploading(true);
    onBusyChange(true);
    setError('');
    try {
      const dataUrl = await prepareSkinImage(file);
      const result = await adminApi<{ id: string; url: string }>('/admin-api/skin-assets', {
        method: 'POST',
        body: JSON.stringify({ dataUrl }),
      });
      if (!/^[a-f0-9]{64}$/.test(result.id))
        throw new Error('Сервер вернул некорректное изображение.');
      appendImage(result.id);
    } catch (reason) {
      const message =
        reason instanceof Error ? reason.message : 'Не удалось загрузить изображение.';
      if (message === 'Войдите в админ-панель.') onUnauthorized();
      else setError(message);
    } finally {
      setUploading(false);
      onBusyChange(false);
    }
  }

  return (
    <section
      className={styles.root}
      data-testid="skin-design-editor"
      aria-label="Редактор композиции"
    >
      <div
        className={styles.tabs}
        role="tablist"
        aria-label="Поверхность оформления"
        data-testid="skin-surface-tabs"
      >
        {surfaces.map(([id, label]) => (
          <button
            type="button"
            role="tab"
            key={id}
            data-testid={`skin-surface-${id}`}
            aria-selected={surface === id}
            aria-controls="skin-surface-panel"
            id={`skin-tab-${id}`}
            tabIndex={surface === id ? 0 : -1}
            disabled={locked}
            className={id === 'board' ? styles.boardTab : undefined}
            onClick={() => {
              setSurface(id);
              setSelectedId(null);
              setError('');
            }}
            onKeyDown={(event) => {
              if (!['ArrowLeft', 'ArrowRight', 'Home', 'End'].includes(event.key)) return;
              event.preventDefault();
              const current = surfaces.findIndex(([name]) => name === id);
              const next =
                event.key === 'Home'
                  ? 0
                  : event.key === 'End'
                    ? surfaces.length - 1
                    : (current + (event.key === 'ArrowRight' ? 1 : -1) + surfaces.length) %
                      surfaces.length;
              const nextSurface = surfaces[next][0];
              setSurface(nextSurface);
              setSelectedId(null);
              setError('');
              document.getElementById(`skin-tab-${nextSurface}`)?.focus();
            }}
          >
            {label}
          </button>
        ))}
      </div>
      <fieldset
        className={styles.surfacePanel}
        id="skin-surface-panel"
        role="tabpanel"
        aria-labelledby={`skin-tab-${surface}`}
        disabled={locked}
      >
        <div className={styles.patternFields}>
          <label className={styles.field}>
            Узор
            <select
              aria-label="Узор поверхности"
              data-testid="skin-pattern"
              value={part.pattern}
              onChange={(event) => updateSurface({ pattern: event.target.value as Pattern })}
            >
              {PATTERNS.map((pattern) => (
                <option key={pattern} value={pattern}>
                  {patternNames[pattern]}
                </option>
              ))}
            </select>
          </label>
          <label className={styles.color}>
            Цвет узора
            <input
              type="color"
              aria-label="Цвет узора"
              value={part.ink}
              onChange={(event) => updateSurface({ ink: event.target.value })}
            />
          </label>
        </div>
        {part.pattern !== 'none' && (
          <div className={styles.twoColumns}>
            <Slider
              label="Масштаб узора"
              value={part.patternScale}
              min={0.5}
              max={3}
              step={0.05}
              suffix="×"
              onChange={(patternScale) => updateSurface({ patternScale })}
            />
            <Slider
              label="Насыщенность узора"
              value={part.patternOpacity}
              onChange={(patternOpacity) => updateSurface({ patternOpacity })}
            />
          </div>
        )}
        <label className={styles.checkbox}>
          <input
            type="checkbox"
            aria-label="Декоративная рамка"
            checked={part.border}
            onChange={(event) => updateSurface({ border: event.target.checked })}
          />
          Декоративная рамка
        </label>
        <div className={styles.twoColumns}>
          <Slider
            label="Матовая поверхность"
            value={part.roughness}
            onChange={(roughness) => updateSurface({ roughness })}
          />
          <Slider
            label="Металличность"
            value={part.metalness}
            onChange={(metalness) => updateSurface({ metalness })}
          />
        </div>
        <div className={styles.sectionHeading}>
          <h3>Декор</h3>
          <span>{part.layers.length} / 12</span>
        </div>
        <div className={styles.addLayer}>
          <select
            aria-label="Добавляемая фигура"
            value={motif}
            onChange={(event) => setMotif(event.target.value as Motif)}
          >
            {MOTIFS.map((kind) => (
              <option key={kind} value={kind}>
                {motifNames[kind]}
              </option>
            ))}
          </select>
          <button
            type="button"
            disabled={part.layers.length >= 12}
            onClick={() => appendLayer(motifLayer(motif, part.ink, freshId()))}
          >
            <Plus size={15} />
            Добавить фигуру
          </button>
        </div>
        <input
          ref={fileInput}
          type="file"
          hidden
          data-testid="skin-image-upload"
          aria-label="Файл изображения для стиля"
          accept="image/png,image/jpeg,image/webp"
          onChange={(event) => {
            const file = event.target.files?.[0];
            event.target.value = '';
            void upload(file);
          }}
        />
        <button
          className={styles.upload}
          type="button"
          disabled={part.layers.length >= 12 || images.length >= MAX_DESIGN_IMAGES}
          onClick={() => fileInput.current?.click()}
        >
          {uploading ? (
            <LoaderCircle size={16} className={styles.spinner} />
          ) : (
            <ImagePlus size={16} />
          )}
          {uploading ? 'Загрузка изображения…' : 'Добавить изображение'}
        </button>
        <p className={styles.hint}>
          PNG, JPEG или WebP. Прозрачный фон подходит для эмблем и орнаментов.
        </p>
        {images.length > 0 && (
          <section className={styles.imageLibrary} aria-label="Изображения стиля">
            <div className={styles.sectionHeading}>
              <h3>Изображения стиля</h3>
              <span>
                {images.length} / {MAX_DESIGN_IMAGES}
              </span>
            </div>
            <div>
              {images.map((id, index) => (
                <button
                  type="button"
                  key={id}
                  aria-label={`Добавить изображение ${index + 1} из стиля`}
                  disabled={part.layers.length >= 12}
                  onClick={() => appendImage(id)}
                >
                  <img src={`/appearance/assets/${id}`} alt="" />
                </button>
              ))}
            </div>
          </section>
        )}
        {error && (
          <p role="alert" className={styles.error}>
            {error}
          </p>
        )}
        {part.layers.length > 0 && (
          <ol className={styles.layers} data-testid="skin-layers" aria-label="Слои декора">
            {part.layers.map((layer, index) => (
              <li key={layer.id} data-testid={`skin-layer-${layer.id}`}>
                <button
                  type="button"
                  className={styles.layerSelect}
                  aria-pressed={selected?.id === layer.id}
                  aria-label={`Редактировать слой ${index + 1}: ${layerName(layer)}`}
                  onClick={() => setSelectedId(layer.id)}
                >
                  {layer.kind === 'image' ? (
                    <img src={`/appearance/assets/${layer.imageId}`} alt="" />
                  ) : (
                    <span className={styles.motifBadge} style={{ color: layer.color }}>
                      {layer.kind === 'motif' &&
                        {
                          moon: '☽',
                          sun: '☀',
                          star: '✧',
                          lotus: '❧',
                          laurel: '❦',
                          diamond: '◇',
                          rings: '◎',
                        }[layer.motif]}
                    </span>
                  )}
                  <span>
                    {index + 1}. {layerName(layer)}
                  </span>
                </button>
                <div className={styles.layerActions}>
                  <button
                    type="button"
                    aria-label={`Поднять слой ${index + 1}`}
                    disabled={index === part.layers.length - 1}
                    onClick={() => moveLayer(layer.id, 1)}
                  >
                    <ArrowUp size={14} />
                  </button>
                  <button
                    type="button"
                    aria-label={`Опустить слой ${index + 1}`}
                    disabled={index === 0}
                    onClick={() => moveLayer(layer.id, -1)}
                  >
                    <ArrowDown size={14} />
                  </button>
                  <button
                    type="button"
                    aria-label={`Удалить слой ${index + 1}`}
                    onClick={() =>
                      updateSurface({ layers: part.layers.filter((item) => item.id !== layer.id) })
                    }
                  >
                    <Trash2 size={14} />
                  </button>
                </div>
              </li>
            ))}
          </ol>
        )}
        {part.layers.length > 1 && (
          <p className={styles.hint}>Последний слой рисуется поверх предыдущих.</p>
        )}
        {selected && (
          <section
            className={styles.layerControls}
            data-testid="skin-layer-controls"
            aria-label="Настройки слоя"
          >
            <div className={styles.sectionHeading}>
              <h3>{layerName(selected)}</h3>
              <button
                type="button"
                aria-label="Дублировать слой"
                disabled={part.layers.length >= 12}
                onClick={() => appendLayer({ ...selected, id: freshId() })}
              >
                <Copy size={14} />
              </button>
            </div>
            {selected.kind === 'motif' && (
              <label className={styles.field}>
                Фигура
                <select
                  aria-label="Фигура слоя"
                  value={selected.motif}
                  onChange={(event) => updateLayer({ motif: event.target.value as Motif })}
                >
                  {MOTIFS.map((kind) => (
                    <option key={kind} value={kind}>
                      {motifNames[kind]}
                    </option>
                  ))}
                </select>
              </label>
            )}
            <label className={styles.field}>
              Расположение
              <select
                aria-label="Повторение слоя"
                value={selected.placement}
                onChange={(event) => updateLayer({ placement: event.target.value as Placement })}
              >
                <option value="single">Одна эмблема</option>
                <option value="corners">По углам</option>
                <option value="grid">Повторяющийся узор</option>
              </select>
            </label>
            <div className={styles.twoColumns}>
              <Slider
                label="Положение по горизонтали"
                value={selected.x}
                onChange={(x) => updateLayer({ x })}
              />
              <Slider
                label="Положение по вертикали"
                value={selected.y}
                onChange={(y) => updateLayer({ y })}
              />
              <Slider
                label="Размер слоя"
                value={selected.size}
                min={0.05}
                onChange={(size) => updateLayer({ size })}
              />
              <Slider
                label="Непрозрачность слоя"
                value={selected.opacity}
                onChange={(opacity) => updateLayer({ opacity })}
              />
            </div>
            <Slider
              label="Поворот слоя"
              value={selected.rotation}
              min={-180}
              max={180}
              step={1}
              suffix="°"
              onChange={(rotation) => updateLayer({ rotation })}
            />
            {selected.kind === 'image' && (
              <label className={styles.checkbox}>
                <input
                  type="checkbox"
                  aria-label="Перекрасить изображение"
                  checked={selected.tint}
                  onChange={(event) => updateLayer({ tint: event.target.checked })}
                />
                Перекрасить изображение
              </label>
            )}
            {(selected.kind === 'motif' || selected.tint) && (
              <label className={styles.color}>
                Цвет декора
                <input
                  type="color"
                  aria-label="Цвет декора"
                  value={selected.color}
                  onChange={(event) => updateLayer({ color: event.target.value })}
                />
              </label>
            )}
          </section>
        )}
        <button
          type="button"
          className={styles.reset}
          onClick={() => {
            updateSurface(blankDesign(part.ink).surfaces[surface]);
            setSelectedId(null);
          }}
        >
          Очистить поверхность
        </button>
      </fieldset>
    </section>
  );
}
